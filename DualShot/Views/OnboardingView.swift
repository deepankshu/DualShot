import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: RecordingSettings
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        .init(
            icon: "video.fill",
            iconColor: .red,
            title: "One Take.\nBoth Frames.",
            body: "DualShot records 16:9 landscape and 9:16 portrait video simultaneously — from a single camera session, with zero quality loss."
        ),
        .init(
            icon: "rectangle.split.2x1.fill",
            iconColor: .blue,
            title: "Two Videos,\nInstantly.",
            body: "Get a YouTube-ready horizontal file and an Instagram Reels-ready vertical file every single time you hit record. No re-shoots."
        ),
        .init(
            icon: "pip.fill",
            iconColor: .purple,
            title: "Live Dual\nPreview.",
            body: "A picture-in-picture overlay shows exactly what your portrait crop looks like while you frame the shot."
        ),
        .init(
            icon: "square.and.arrow.down.fill",
            iconColor: .green,
            title: "Auto-Save\nto Camera Roll.",
            body: "Both videos land in your Camera Roll the moment you stop recording — named and ready to share."
        )
    ]

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color(white: 0.05), Color(white: 0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, p in
                        OnboardingPageView(page: p)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                // Dots + button
                VStack(spacing: 24) {
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            Capsule()
                                .fill(i == page ? Color.white : Color.white.opacity(0.3))
                                .frame(width: i == page ? 20 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: page)
                        }
                    }

                    Button(action: advance) {
                        HStack {
                            Text(page == pages.count - 1 ? "Get Started" : "Next")
                                .font(.headline)
                            if page == pages.count - 1 {
                                Image(systemName: "video.fill")
                            } else {
                                Image(systemName: "chevron.right")
                            }
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 44)
            }
        }
    }

    private func advance() {
        if page < pages.count - 1 {
            withAnimation(.spring()) { page += 1 }
        } else {
            settings.hasSeenOnboarding = true
            settings.save()
        }
    }
}

// MARK: - Page model
private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let body: String
}

// MARK: - Single page view
private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(page.iconColor.opacity(0.15))
                    .frame(width: 110, height: 110)
                Image(systemName: page.icon)
                    .font(.system(size: 52))
                    .foregroundColor(page.iconColor)
            }

            // Text
            VStack(spacing: 14) {
                Text(page.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Text(page.body)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
    }
}
