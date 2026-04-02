import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: RecordingSettings
    @EnvironmentObject var camera: CameraManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                // ── Output Quality ─────────────────────────────────────────
                Section {
                    Picker("Quality", selection: $settings.quality) {
                        ForEach(VideoQuality.allCases, id: \.self) { q in
                            HStack {
                                Image(systemName: q == .uhd4K ? "4k.tv.fill" : "tv.fill")
                                Text(q.rawValue)
                            }
                            .tag(q)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.quality == .uhd4K
                             ? "Landscape: 3840×2160  ·  Portrait: 1080×1920"
                             : "Landscape: 1920×1080  ·  Portrait: 1080×1920")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if settings.quality == .uhd4K {
                            Text("4K requires a device with a 4K-capable rear camera.")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                } header: {
                    Label("Output Quality", systemImage: "film.stack")
                }

                // ── PiP Position ───────────────────────────────────────────
                Section {
                    Picker("PiP Position", selection: $settings.pipPosition) {
                        ForEach(PiPPosition.allCases, id: \.self) { pos in
                            Text(pos.rawValue).tag(pos)
                        }
                    }
                } header: {
                    Label("Portrait Preview (PiP)", systemImage: "pip")
                } footer: {
                    Text("Choose which corner the 9:16 preview sits in while recording.")
                }

                // ── Watermark ──────────────────────────────────────────────
                Section {
                    Toggle("Enable Watermark", isOn: $settings.watermarkEnabled)
                    if settings.watermarkEnabled {
                        HStack {
                            TextField("Watermark text", text: $settings.watermarkText)
                                .autocorrectionDisabled()
                            if !settings.watermarkText.isEmpty {
                                Button { settings.watermarkText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Appears bottom-right on both output videos.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Watermark / Branding", systemImage: "textformat")
                }

                // ── About ──────────────────────────────────────────────────
                Section {
                    LabeledContent("App", value: "DualShot")
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Tagline", value: "One take. Both frames.")
                } header: {
                    Label("About", systemImage: "info.circle")
                }

                // ── Reset onboarding (dev helper) ─────────────────────────
                #if DEBUG
                Section {
                    Button("Reset Onboarding", role: .destructive) {
                        settings.hasSeenOnboarding = false
                        settings.save()
                        dismiss()
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        settings.save()
                        // Reconfigure session if quality changed
                        if !camera.isRecording {
                            camera.setupSession(quality: settings.quality)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
