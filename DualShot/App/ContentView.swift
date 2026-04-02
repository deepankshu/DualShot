import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: RecordingSettings
    @EnvironmentObject var camera: CameraManager

    var body: some View {
        Group {
            if settings.hasSeenOnboarding {
                RecordingView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut, value: settings.hasSeenOnboarding)
    }
}
