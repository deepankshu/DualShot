import AVFoundation
import CoreImage
import UIKit

/// Receives raw camera frames and writes two simultaneous video files:
///   • Horizontal (16:9) — the full source frame
///   • Vertical   (9:16) — a center-cropped, scaled-to-1080×1920 version
final class DualVideoWriter {

    // MARK: - Init params
    private let horizontalURL: URL
    private let verticalURL: URL
    private let sourceSize: CGSize       // e.g. 1920×1080 or 3840×2160
    private let watermarkEnabled: Bool
    private let watermarkText: String

    // MARK: - Writers
    private var hWriter: AVAssetWriter?
    private var vWriter: AVAssetWriter?

    private var hVideoInput: AVAssetWriterInput?
    private var vVideoInput: AVAssetWriterInput?
    private var hAudioInput: AVAssetWriterInput?
    private var vAudioInput: AVAssetWriterInput?

    private var hAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var vAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    // MARK: - State
    private var isWriting = false
    private var sessionStartTime: CMTime?

    // Portrait output is always 1080×1920 (9:16 standard)
    private let portraitOutputSize = CGSize(width: 1080, height: 1920)

    // Shared CIContext — reusing across frames is important for performance
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Init
    init(horizontalURL: URL,
         verticalURL: URL,
         sourceSize: CGSize,
         watermarkEnabled: Bool,
         watermarkText: String) {
        self.horizontalURL   = horizontalURL
        self.verticalURL     = verticalURL
        self.sourceSize      = sourceSize
        self.watermarkEnabled = watermarkEnabled
        self.watermarkText   = watermarkText
    }

    // MARK: - Public API
    func startWriting() {
        guard !isWriting else { return }
        setupWriters()
        isWriting = true
        sessionStartTime = nil
    }

    func appendVideo(sampleBuffer: CMSampleBuffer) {
        guard isWriting else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Start sessions on the first video frame
        if sessionStartTime == nil {
            sessionStartTime = pts
            hWriter?.startSession(atSourceTime: pts)
            vWriter?.startSession(atSourceTime: pts)
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // ── Landscape ──────────────────────────────────────────────────────
        if let hInput = hVideoInput, hInput.isReadyForMoreMediaData {
            if watermarkEnabled,
               let pool = hAdaptor?.pixelBufferPool,
               let stamped = watermarked(pixelBuffer, pool: pool, size: sourceSize) {
                hAdaptor?.append(stamped, withPresentationTime: pts)
            } else {
                // Zero-copy path: pass original CVPixelBuffer directly
                hAdaptor?.append(pixelBuffer, withPresentationTime: pts)
            }
        }

        // ── Portrait (center-crop + scale to 1080×1920) ────────────────────
        if let vInput = vVideoInput, vInput.isReadyForMoreMediaData,
           let pool = vAdaptor?.pixelBufferPool,
           let cropped = portraitCrop(pixelBuffer, pool: pool) {
            vAdaptor?.append(cropped, withPresentationTime: pts)
        }
    }

    func appendAudio(sampleBuffer: CMSampleBuffer) {
        guard isWriting, sessionStartTime != nil else { return }

        if let hAI = hAudioInput, hAI.isReadyForMoreMediaData {
            hAI.append(sampleBuffer)
        }
        if let vAI = vAudioInput, vAI.isReadyForMoreMediaData {
            vAI.append(sampleBuffer)
        }
    }

    func finishWriting(completion: @escaping (URL?, URL?) -> Void) {
        guard isWriting else {
            completion(nil, nil)
            return
        }
        isWriting = false

        let group = DispatchGroup()

        group.enter()
        hVideoInput?.markAsFinished()
        hAudioInput?.markAsFinished()
        hWriter?.finishWriting { group.leave() }

        group.enter()
        vVideoInput?.markAsFinished()
        vAudioInput?.markAsFinished()
        vWriter?.finishWriting { group.leave() }

        group.notify(queue: .main) { [weak self] in
            completion(self?.horizontalURL, self?.verticalURL)
        }
    }

    // MARK: - Setup helpers
    private func setupWriters() {
        [horizontalURL, verticalURL].forEach { try? FileManager.default.removeItem(at: $0) }

        hWriter = try? AVAssetWriter(outputURL: horizontalURL, fileType: .mp4)
        vWriter = try? AVAssetWriter(outputURL: verticalURL,   fileType: .mp4)

        let audioSettings: [String: Any] = [
            AVFormatIDKey:              kAudioFormatMPEG4AAC,
            AVSampleRateKey:            44100,
            AVNumberOfChannelsKey:      2,
            AVEncoderBitRateKey:        128_000
        ]

        // ── Horizontal inputs ──────────────────────────────────────────────
        let hVideoSettings = videoSettings(size: sourceSize)
        hVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: hVideoSettings)
        hVideoInput?.expectsMediaDataInRealTime = true

        hAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        hAudioInput?.expectsMediaDataInRealTime = true

        hAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: hVideoInput!,
            sourcePixelBufferAttributes: pixelBufferAttributes(size: sourceSize)
        )

        // ── Portrait inputs ────────────────────────────────────────────────
        let vVideoSettings = videoSettings(size: portraitOutputSize)
        vVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: vVideoSettings)
        vVideoInput?.expectsMediaDataInRealTime = true

        vAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        vAudioInput?.expectsMediaDataInRealTime = true

        vAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vVideoInput!,
            sourcePixelBufferAttributes: pixelBufferAttributes(size: portraitOutputSize)
        )

        // Add to writers
        [hVideoInput, hAudioInput].compactMap { $0 }.forEach { inp in
            if hWriter?.canAdd(inp) == true { hWriter?.add(inp) }
        }
        [vVideoInput, vAudioInput].compactMap { $0 }.forEach { inp in
            if vWriter?.canAdd(inp) == true { vWriter?.add(inp) }
        }

        hWriter?.startWriting()
        vWriter?.startWriting()
    }

    private func videoSettings(size: CGSize) -> [String: Any] {
        let megapixels = size.width * size.height
        let bitrate: Int
        switch megapixels {
        case ..<(1920 * 1080 + 1):  bitrate = 10_000_000   // ≤1080p
        default:                    bitrate = 40_000_000   // 4K
        }
        return [
            AVVideoCodecKey:   AVVideoCodecType.h264,
            AVVideoWidthKey:   Int(size.width),
            AVVideoHeightKey:  Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:  bitrate,
                AVVideoProfileLevelKey:    AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]
    }

    private func pixelBufferAttributes(size: CGSize) -> [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey  as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
    }

    // MARK: - Frame processing
    /// Crop the center 9:16 stripe from a landscape frame and scale to 1080×1920.
    private func portraitCrop(_ src: CVPixelBuffer, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        let srcW = CGFloat(CVPixelBufferGetWidth(src))
        let srcH = CGFloat(CVPixelBufferGetHeight(src))

        // Center crop: width = srcH × (9/16), height = srcH
        let cropW = srcH * 9.0 / 16.0
        let cropX = (srcW - cropW) / 2.0
        let cropRect = CGRect(x: cropX, y: 0, width: cropW, height: srcH)

        var image = CIImage(cvPixelBuffer: src)
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropX, y: 0))

        // Scale to 1080×1920
        let sx = portraitOutputSize.width  / cropW
        let sy = portraitOutputSize.height / srcH
        image = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        if watermarkEnabled {
            image = overlayWatermark(on: image,
                                     outputSize: portraitOutputSize,
                                     text: watermarkText)
        }

        return render(image, to: pool, size: portraitOutputSize)
    }

    /// Apply watermark to a full-size landscape frame.
    private func watermarked(_ src: CVPixelBuffer,
                              pool: CVPixelBufferPool,
                              size: CGSize) -> CVPixelBuffer? {
        var image = CIImage(cvPixelBuffer: src)
        image = overlayWatermark(on: image, outputSize: size, text: watermarkText)
        return render(image, to: pool, size: size)
    }

    /// Render a CIImage into a pooled CVPixelBuffer.
    private func render(_ image: CIImage,
                         to pool: CVPixelBufferPool,
                         size: CGSize) -> CVPixelBuffer? {
        var outBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outBuffer) == kCVReturnSuccess,
              let buffer = outBuffer else { return nil }
        ciContext.render(image, to: buffer)
        return buffer
    }

    // MARK: - Watermark
    private func overlayWatermark(on image: CIImage,
                                   outputSize: CGSize,
                                   text: String) -> CIImage {
        guard !text.isEmpty else { return image }

        let scale = outputSize.width / 1080.0   // normalise to 1080px base
        let fontSize: CGFloat = 36 * scale
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            UIFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: UIColor.white.withAlphaComponent(0.75)
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let renderer = UIGraphicsImageRenderer(size: textSize)
        let textImg  = renderer.image { ctx in
            (text as NSString).draw(at: .zero, withAttributes: attrs)
        }
        guard let ciText = CIImage(image: textImg) else { return image }

        let margin: CGFloat = 20 * scale
        // Position bottom-right (CIImage y=0 is bottom)
        let tx = outputSize.width  - textSize.width  - margin
        let ty = margin
        let placed = ciText.transformed(by: CGAffineTransform(translationX: tx, y: ty))
        return placed.composited(over: image)
    }
}
