import SwiftUI
import AVFoundation

struct RecordingView: View {
    @EnvironmentObject var camera: CameraManager
    @EnvironmentObject var settings: RecordingSettings
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ── Full-screen landscape preview ─────────────────────────────
            LandscapePreviewView(session: camera.session)
                .ignoresSafeArea()

            // ── Portrait PiP ──────────────────────────────────────────────
            PiPOverlay(session: camera.session, position: settings.pipPosition)

            // ── HUD ───────────────────────────────────────────────────────
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }

            // ── Saved banner ──────────────────────────────────────────────
            if camera.showSavedBanner {
                SavedBanner()
            }

            // ── Permission denied overlay ─────────────────────────────────
            if camera.authorizationStatus == .denied {
                PermissionDeniedView()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(camera)
        }
        .onAppear {
            if camera.authorizationStatus == .authorized && !camera.session.isRunning {
                camera.setupSession(quality: settings.quality)
            }
        }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack(alignment: .center) {
            if camera.isRecording {
                RecordingTimer(duration: camera.recordingDuration)
                    .transition(.opacity)
            }
            Spacer()
            if !camera.isRecording {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .animation(.easeInOut(duration: 0.25), value: camera.isRecording)
    }

    // MARK: - Bottom bar
    private var bottomBar: some View {
        HStack {
            // Format labels
            VStack(alignment: .leading, spacing: 4) {
                FormatBadge(label: "16:9", sub: "Landscape", color: .blue)
                FormatBadge(label: "9:16", sub: "Portrait",  color: .purple)
            }
            .opacity(camera.isRecording ? 0.6 : 1)

            Spacer()

            // Record button
            RecordButton(isRecording: camera.isRecording) {
                if camera.isRecording {
                    camera.stopRecording()
                } else {
                    camera.startRecording(settings: settings)
                }
            }

            Spacer()

            // Spacer twin to balance the layout
            VStack(alignment: .leading, spacing: 4) {
                FormatBadge(label: "16:9", sub: "Landscape", color: .blue)
                FormatBadge(label: "9:16", sub: "Portrait",  color: .purple)
            }
            .hidden()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 32)
    }
}

// MARK: - PiP overlay
private struct PiPOverlay: View {
    let session: AVCaptureSession
    let position: PiPPosition

    private var alignment: Alignment {
        switch position {
        case .topLeft:     return .topLeading
        case .topRight:    return .topTrailing
        case .bottomLeft:  return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                // PiP preview box (9:16)
                PortraitPiPPreviewView(session: session)
                    .frame(width: 84, height: 84 * 16 / 9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)

                // "9:16" label below the box
                Text("9:16")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(4)
                    .padding(.top, 4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        }
    }
}

// MARK: - Record button
private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 76, height: 76)

                if isRecording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red)
                        .frame(width: 30, height: 30)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)
    }
}

// MARK: - Timer
private struct RecordingTimer: View {
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .opacity(duration.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.3)
                .animation(.easeInOut(duration: 0.5).repeatForever(), value: duration)

            Text(formatted)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }

    private var formatted: String {
        let t = Int(duration)
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Format badge
private struct FormatBadge: View {
    let label: String
    let sub: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.45))
        .cornerRadius(6)
    }
}

// MARK: - Saved banner
private struct SavedBanner: View {
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Both videos saved")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("Horizontal + Vertical in Camera Roll")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(), value: true)
    }
}

// MARK: - Permission denied
private struct PermissionDeniedView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.white.opacity(0.6))
                Text("Camera Access Required")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                Text("Please enable camera access in Settings to use DualShot.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.headline)
                .foregroundColor(.black)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color.white)
                .cornerRadius(12)
            }
        }
    }
}
