import VisionBridgeKit
import SwiftUI

/// Live text dump of the latest `FramePayload` for debugging vision / contract output.
struct DetectionDebugView: View {
    @ObservedObject var session: VisionBridgeSession

    var body: some View {
        ScrollView {
            Text(debugBody)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(16)
        }
        .background(VisionBridgeTheme.background)
        .navigationTitle("Detections")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var debugBody: String {
        guard let p = session.lastPayload else {
            return "No frame yet.\n\nStart the camera so the vision pipeline publishes payloads."
        }
        var lines: [String] = []
        lines.append("frame_id: \(p.frameId)")
        lines.append("timestamp_ms: \(p.timestampMs)")
        lines.append("vision_duration_ms: \(p.visionDurationMs)")
        if let cam = p.camera {
            lines.append("camera.lens_status: \(cam.lensStatus)")
            lines.append("camera.lens_laplacian_var: \(formatNum(cam.lensLaplacianVar))")
            if let a = cam.lensAnnounce, !a.isEmpty {
                lines.append("camera.lens_announce: \(a)")
            }
        } else {
            lines.append("camera: (nil)")
        }
        lines.append("")
        lines.append("objects (\(p.objects.count)):")
        if p.objects.isEmpty {
            lines.append("  (empty)")
        }
        for (i, o) in p.objects.enumerated() {
            lines.append("")
            lines.append("[\(i)] object_id: \(o.objectId)")
            lines.append("    class: \(o.objectClass)")
            lines.append("    confidence: \(formatNum(o.confidence))")
            lines.append("    distance_m: \(formatNum(o.distanceM))")
            lines.append("    pan_value: \(formatNum(o.panValue))")
            lines.append("    velocity_mps: \(formatNum(o.velocityMps))")
            lines.append("    priority: \(o.priority)")
            let b = o.bbox
            lines.append("    bbox: x=\(formatNum(b.xCenterNorm)) y=\(formatNum(b.yCenterNorm)) w=\(formatNum(b.widthNorm)) h=\(formatNum(b.heightNorm))")
        }
        return lines.joined(separator: "\n")
    }

    private func formatNum(_ v: Double) -> String {
        String(format: "%.4g", v)
    }
}
