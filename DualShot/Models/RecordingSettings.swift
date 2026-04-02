import Foundation
import Combine

enum VideoQuality: String, CaseIterable {
    case hd1080p = "1080p"
    case uhd4K = "4K"
}

enum PiPPosition: String, CaseIterable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
}

class RecordingSettings: ObservableObject {
    @Published var quality: VideoQuality = .hd1080p
    @Published var pipPosition: PiPPosition = .topRight
    @Published var watermarkEnabled: Bool = false
    @Published var watermarkText: String = "DualShot"
    @Published var hasSeenOnboarding: Bool = false

    init() {
        load()
    }

    func load() {
        if let raw = UserDefaults.standard.string(forKey: "ds_quality"),
           let q = VideoQuality(rawValue: raw) { quality = q }
        if let raw = UserDefaults.standard.string(forKey: "ds_pipPosition"),
           let p = PiPPosition(rawValue: raw) { pipPosition = p }
        watermarkEnabled = UserDefaults.standard.bool(forKey: "ds_watermarkEnabled")
        watermarkText = UserDefaults.standard.string(forKey: "ds_watermarkText") ?? "DualShot"
        hasSeenOnboarding = UserDefaults.standard.bool(forKey: "ds_hasSeenOnboarding")
    }

    func save() {
        UserDefaults.standard.set(quality.rawValue, forKey: "ds_quality")
        UserDefaults.standard.set(pipPosition.rawValue, forKey: "ds_pipPosition")
        UserDefaults.standard.set(watermarkEnabled, forKey: "ds_watermarkEnabled")
        UserDefaults.standard.set(watermarkText, forKey: "ds_watermarkText")
        UserDefaults.standard.set(hasSeenOnboarding, forKey: "ds_hasSeenOnboarding")
    }
}
