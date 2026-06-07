import SwiftUI
#if os(iOS)
import UIKit
#endif

/// On-screen stats for a live demo or debug: object count, vision latency, lens line.
/// Add as an overlay in your lanyard UI; Hearing still consumes `lastPayload` directly.
@MainActor
public struct PayloadHUD: View {
    @ObservedObject public var session: VisionBridgeSession
    /// When `false`, high-priority frame haptics are skipped (e.g. global haptics off in Settings).
    public var hapticsEnabled: Bool
    @State private var lastHighHapticFrame: Int = -1

    public init(session: VisionBridgeSession, hapticsEnabled: Bool = true) {
        self._session = ObservedObject(wrappedValue: session)
        self.hapticsEnabled = hapticsEnabled
    }

    public var body: some View {
        if let p = session.lastPayload {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    stat("\(p.objects.count)", "objects")
                    stat("\(p.visionDurationMs) ms", "vision")
                }
                if let cam = p.camera, cam.lensStatus != "ok" {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(shortLens(cam: cam))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Text("…")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func shortLens(cam: CameraHealthDTO) -> String {
        if let a = cam.lensAnnounce, !a.isEmpty { return a }
        return "Lens: \(cam.lensStatus) · var \(String(format: "%.0f", cam.lensLaplacianVar))"
    }
}
