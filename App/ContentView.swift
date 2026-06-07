import VisionBridgeKit
import SwiftUI

struct ContentView: View {
    @AppStorage("shouldShowOnboarding") private var shouldShowOnboarding: Bool = true
    @EnvironmentObject private var app: AppViewModel
    @EnvironmentObject private var hearing: HearingEngine
    @State private var showingSettings = false
    @AppStorage(VisionBridgeFeatureKey.payloadHUD) private var showPayloadHUD: Bool = false
    @AppStorage(VisionBridgeFeatureKey.haptics) private var hapticsOn: Bool = true
    @State private var speechMutedBanner = false

    var body: some View {
        Group {
            if shouldShowOnboarding {
                OnboardingView(shouldShowOnboarding: $shouldShowOnboarding)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                mainDashboard
                    .onAppear {
                        app.ensureCameraPreview()
                    }
                    .sheet(isPresented: $showingSettings) {
                        SettingsView()
                            .environmentObject(app)
                    }
            }
        }
        .onDisappear {
            app.setScanning(false)
            app.stopCameraPreview()
        }
    }

    private var mainDashboard: some View {
        NavigationStack {
            ZStack {
                VisionBridgeTheme.background.ignoresSafeArea()
                ZStack {
                    RadialGradient(
                        colors: [VisionBridgeTheme.accent.opacity(0.12), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 450
                    )
                    RadialGradient(
                        colors: [VisionBridgeTheme.info.opacity(0.08), .clear],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: 600
                    )
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 12) {
                    safetyDisclaimer
                    if speechMutedBanner {
                        mutedBanner
                    }
                    if !app.modelAvailable { modelCallout }
                    cameraPanel
                    scanDock
                    if showPayloadHUD, app.modelAvailable, let s = app.session {
                        PayloadHUD(session: s, hapticsEnabled: hapticsOn)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .overlay(alignment: .topLeading) {
                TwoFingerDoubleTapCapture {
                    hearing.muteFor(seconds: 10)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        speechMutedBanner = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            speechMutedBanner = false
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Bridge")
                        .font(.system(size: 32, weight: .bold))
                        .lineLimit(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        if app.modelAvailable, let session = app.session {
                            NavigationLink {
                                DetectionDebugView(session: session)
                            } label: {
                                Image(systemName: "list.bullet.rectangle")
                                    .font(.body.weight(.semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .frame(width: 40, height: 40)
                                    .background {
                                        Circle()
                                            .fill(Color.white.opacity(0.06))
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Detection debug")
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.body.weight(.semibold))
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 40, height: 40)
                                .background {
                                    Circle()
                                        .fill(Color.white.opacity(0.06))
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Settings")
                    }
                }
            }
        }
        .tint(VisionBridgeTheme.accent)
        .preferredColorScheme(.dark)
    }

    private var safetyDisclaimer: some View {
        Text("Assistive only. Distances are estimated and this does not replace a cane, guide dog, or orientation training.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
            .accessibilityLabel("Safety note. Assistive only. Distances are estimated and this does not replace cane or guide dog.")
    }

    private var mutedBanner: some View {
        HStack {
            Image(systemName: "speaker.slash.fill")
            Text("Speech muted for 10 seconds")
            Spacer()
            Text("Tap to unmute")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.semibold))
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .onTapGesture {
            hearing.unmuteNow()
            withAnimation(.easeInOut(duration: 0.2)) {
                speechMutedBanner = false
            }
        }
    }

    private var modelCallout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(VisionBridgeTheme.warmAlert)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add the vision model")
                        .font(.headline)
                    Text("Include yolov8m-oiv7.mlpackage (from scripts/export_coreml.py) in this app in Xcode, then build again. Optional lab setup is in Settings if your team needs it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: VisionBridgeTheme.cornerL, style: .continuous)
                .fill(VisionBridgeTheme.warmAlert.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: VisionBridgeTheme.cornerL, style: .continuous)
                .strokeBorder(VisionBridgeTheme.warmAlert.opacity(0.3), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var cameraPanel: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Camera")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if app.isScanning {
                    Label("LIVE", systemImage: "record.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(VisionBridgeTheme.warmAlert)
                }
            }
            cameraSquare
        }
        #endif
    }

    @ViewBuilder
    private var cameraSquare: some View {
        #if os(iOS)
        ZStack {
            Color.black
            if app.modelAvailable, let session = app.captureSessionForPreview {
                CameraFeedPreview(session: session)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(app.modelAvailable ? "Starting camera…" : "Camera preview unavailable")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: VisionBridgeTheme.cornerL, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VisionBridgeTheme.cornerL, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
        .accessibilityLabel(app.isScanning ? "Live camera feed" : "Camera preview")
        #endif
    }

    private var scanDock: some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                app.setScanning(!app.isScanning)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: app.isScanning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                Text(app.isScanning ? "Stop Bridge" : "Start Bridge")
                    .font(.headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(PrimaryDockButtonStyle(isOn: app.isScanning, enabled: app.modelAvailable))
        .disabled(!app.modelAvailable)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(app.isScanning ? "Stop Bridge" : "Start Bridge")
        .accessibilityHint("Double tap to start or stop Bridge. When on, nearby objects are spoken automatically.")
    }
}

// MARK: - Subviews

private struct PrimaryDockButtonStyle: ButtonStyle {
    var isOn: Bool
    var enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isOn ? Color.black : Color.primary.opacity(0.95))
            .background {
                RoundedRectangle(cornerRadius: VisionBridgeTheme.cornerL, style: .continuous)
                    .fill(
                        isOn
                            ? AnyShapeStyle(VisionBridgeTheme.accent)
                            : AnyShapeStyle(Color.white.opacity(0.1))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: VisionBridgeTheme.cornerL, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: isOn ? 0 : 1)
            }
            .scaleEffect(configuration.isPressed && enabled ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.4)
    }
}

#Preview {
    struct PreviewHost: View {
        @StateObject private var app = AppViewModel()
        var body: some View {
            ContentView()
                .environmentObject(app)
                .environmentObject(app.hearing)
        }
    }
    return PreviewHost()
}
