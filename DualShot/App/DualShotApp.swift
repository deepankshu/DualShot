import SwiftUI

@main
struct DualShotApp: App {
    @StateObject private var settings = RecordingSettings()
    @StateObject private var camera   = CameraManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(camera)
                .preferredColorScheme(.dark)
        }
    }
}
