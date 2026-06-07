import SwiftUI

struct OnboardingView: View {
    @Binding var shouldShowOnboarding: Bool
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Spoken Awareness",
            description: "Bridge uses your iPhone camera to detect people, vehicles, and obstacles ahead, then speaks what it sees with direction and estimated distance.",
            icon: "person.badge.shield.checkmark.fill",
            color: VisionBridgeTheme.accent
        ),
        OnboardingPage(
            title: "On-Device Vision",
            description: "Object detection runs entirely on your phone—no internet required. Hazards are prioritized so you hear what matters first.",
            icon: "eye.trianglebadge.exclamationmark.fill",
            color: VisionBridgeTheme.info
        ),
        OnboardingPage(
            title: "Assistive Guidance",
            description: "Bridge adds a layer of awareness—it does not replace a cane or guide dog. Distances are estimates. Two-finger double-tap mutes speech for 10 seconds.",
            icon: "waveform.path.ecg",
            color: VisionBridgeTheme.warmAlert
        ),
    ]

    var body: some View {
        ZStack {
            VisionBridgeTheme.background.ignoresSafeArea()
            RadialGradient(
                colors: [pages[safe: currentPage]?.color.opacity(0.2) ?? VisionBridgeTheme.accent.opacity(0.15), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 400
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.45), value: currentPage)

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        OnboardingContent(page: pages[i])
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Capsule()
                            .fill(i == currentPage ? pages[i].color : Color.white.opacity(0.2))
                            .frame(width: i == currentPage ? 28 : 6, height: 6)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 28)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentPage)

                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { currentPage += 1 }
                    } else {
                        withAnimation(.easeOut(duration: 0.25)) { shouldShowOnboarding = false }
                    }
                } label: {
                    Text(currentPage == pages.count - 1 ? "Start Bridge" : "Continue")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(currentPage == pages.count - 1 ? Color.black : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background {
                            RoundedRectangle(cornerRadius: VisionBridgeTheme.cornerL, style: .continuous)
                                .fill(currentPage == pages.count - 1 ? AnyShapeStyle(VisionBridgeTheme.accent) : AnyShapeStyle(Color.white.opacity(0.12)))
                        }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct OnboardingPage {
    let title: String
    let description: String
    let icon: String
    let color: Color
}

private struct OnboardingContent: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(page.color.opacity(0.12))
                    .frame(width: 140, height: 140)
                Image(systemName: page.icon)
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(page.color)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.bottom, 36)
            VStack(spacing: 14) {
                Text(page.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(page.title). \(page.description)")
            Spacer()
            Spacer()
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        (0..<count).contains(i) ? self[i] : nil
    }
}

#Preview {
    OnboardingView(shouldShowOnboarding: .constant(true))
}
