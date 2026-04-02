import AVFoundation
import Photos
import UIKit

class CameraManager: NSObject, ObservableObject {

    // MARK: - Public state
    let session = AVCaptureSession()
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published var lastHorizontalURL: URL?
    @Published var lastVerticalURL: URL?
    @Published var showSavedBanner = false

    // MARK: - Private
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.dualshot.session", qos: .userInitiated)
    private let videoQueue  = DispatchQueue(label: "com.dualshot.video",   qos: .userInitiated)
    private let audioQueue  = DispatchQueue(label: "com.dualshot.audio",   qos: .userInitiated)

    private var dualWriter: DualVideoWriter?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var currentQuality: VideoQuality = .hd1080p

    // MARK: - Init
    override init() {
        super.init()
        requestAuthorization()
    }

    // MARK: - Authorization
    private func requestAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.authorizationStatus = .authorized }
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted { self?.setupSession() }
                }
            }
        default:
            DispatchQueue.main.async { self.authorizationStatus = .denied }
        }
    }

    // MARK: - Session setup
    func setupSession(quality: VideoQuality = .hd1080p) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.currentQuality = quality

            // Remove existing I/O
            self.session.inputs.forEach  { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }

            self.session.beginConfiguration()
            self.session.sessionPreset = (quality == .uhd4K) ? .hd4K3840x2160 : .hd1920x1080

            // Video input
            guard
                let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                          for: .video, position: .back),
                let videoInput  = try? AVCaptureDeviceInput(device: videoDevice),
                self.session.canAddInput(videoInput)
            else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(videoInput)

            // Audio input
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput  = try? AVCaptureDeviceInput(device: audioDevice),
               self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
            }

            // Video output — raw BGRA so we can crop with CIImage
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            // Stabilise orientation: lock video connection to landscape right
            if let conn = self.videoOutput.connection(with: .video) {
                if conn.isVideoRotationAngleSupported(0) {
                    conn.videoRotationAngle = 0 // landscape
                }
            }

            // Audio output
            self.audioOutput.setSampleBufferDelegate(self, queue: self.audioQueue)
            if self.session.canAddOutput(self.audioOutput) {
                self.session.addOutput(self.audioOutput)
            }

            self.session.commitConfiguration()

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    // MARK: - Recording control
    func startRecording(settings: RecordingSettings) {
        guard !isRecording else { return }

        // Reconfigure session if quality changed
        if settings.quality != currentQuality {
            session.stopRunning()
            setupSession(quality: settings.quality)
            // Give the session a moment to settle before writing
            sessionQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.beginWriter(settings: settings)
            }
        } else {
            beginWriter(settings: settings)
        }
    }

    private func beginWriter(settings: RecordingSettings) {
        let timestamp = DateFormatter.dualShot.string(from: Date())
        let tmp = FileManager.default.temporaryDirectory
        let hURL = tmp.appendingPathComponent("DualShot_Horizontal_\(timestamp).mp4")
        let vURL = tmp.appendingPathComponent("DualShot_Vertical_\(timestamp).mp4")

        let sourceSize: CGSize = (settings.quality == .uhd4K)
            ? CGSize(width: 3840, height: 2160)
            : CGSize(width: 1920, height: 1080)

        dualWriter = DualVideoWriter(
            horizontalURL: hURL,
            verticalURL: vURL,
            sourceSize: sourceSize,
            watermarkEnabled: settings.watermarkEnabled,
            watermarkText: settings.watermarkText
        )
        dualWriter?.startWriting()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isRecording = true
            self.recordingStartTime = Date()
            self.recordingDuration = 0
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let start = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            self?.recordingTimer?.invalidate()
            self?.recordingTimer = nil
        }

        let writer = dualWriter
        dualWriter = nil

        writer?.finishWriting { [weak self] hURL, vURL in
            guard let self else { return }
            // Request photo library access then save
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else { return }
                PHPhotoLibrary.shared().performChanges({
                    if let u = hURL { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: u) }
                    if let u = vURL { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: u) }
                }) { _, _ in
                    DispatchQueue.main.async {
                        self.lastHorizontalURL = hURL
                        self.lastVerticalURL   = vURL
                        self.showSavedBanner   = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            self.showSavedBanner = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sample buffer delegates
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate,
                          AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard isRecording, let writer = dualWriter else { return }

        if output is AVCaptureVideoDataOutput {
            writer.appendVideo(sampleBuffer: sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            writer.appendAudio(sampleBuffer: sampleBuffer)
        }
    }
}

// MARK: - Helpers
private extension DateFormatter {
    static let dualShot: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()
}
