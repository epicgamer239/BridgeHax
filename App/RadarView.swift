import SwiftUI
import VisionBridgeKit

struct RadarView: View {
    /// Real-time hazard payload from the Vision Engine
    var objects: [DetectedObjectDTO]
    /// Whether a critical threat is currently active
    var alertActive: Bool

    @State private var pingScale: CGFloat = 0.5
    @State private var pingOpacity: Double = 0.8

    var body: some View {
        GeometryReader { geo in
            let radarOrigin = CGPoint(x: geo.size.width / 2, y: geo.size.height - 30)
            let maxRadius = geo.size.height - 60
            
            ZStack {
                // ── FOV Cone (The 'Vision' field) ────────────────────────────
                ConeShape(angle: 100)
                    .fill(
                        LinearGradient(
                            colors: [sweepColor.opacity(0.12), sweepColor.opacity(0.01)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: maxRadius * 2, height: maxRadius)
                    .position(x: radarOrigin.x, y: radarOrigin.y - (maxRadius / 2))
                
                // ── Grid Rings ──────────────────────────────────────────────
                ForEach([0.33, 0.66, 1.0], id: \.self) { fraction in
                    Circle()
                        .inset(by: (1.0 - fraction) * maxRadius)
                        .stroke(ringColor.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: maxRadius * 2, height: maxRadius * 2)
                        .position(radarOrigin)
                }

                // ── Sweep arm (Scanner beam) ─────────────────────────────────
                RadarSweepLine(maxRadius: maxRadius, sweepColor: sweepColor)
                    .position(radarOrigin)

                // ── Object blips ─────────────────────────────────────────────
                ForEach(objects, id: \.objectId) { obj in
                    let pos = radarPosition(for: obj, in: maxRadius)
                    RadarBlip(obj: obj, sweepColor: sweepColor)
                        .position(x: radarOrigin.x + pos.x, y: radarOrigin.y + pos.y)
                }

                // ── User position (Origin) ───────────────────────────────────
                Circle()
                    .fill(sweepColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: sweepColor.opacity(0.6), radius: 12)
                    .position(radarOrigin)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nearby objects radar")
    }

    // MARK: - Helpers

    private var sweepColor: Color {
        alertActive ? VisionBridgeTheme.warmAlert : VisionBridgeTheme.accent
    }

    private var ringColor: Color { VisionBridgeTheme.accent }

    /// Maps the real world 3D position to the 2D radar plane relative to origin
    private func radarPosition(for obj: DetectedObjectDTO, in maxRadius: CGFloat) -> CGPoint {
        // Map pan to a wider arc (-50° to +50°)
        let angleDegrees = obj.panValue * 50.0
        let angleRadians = angleDegrees * .pi / 180.0
        
        // Non-linear distance mapping: emphasize closer objects
        let maxDist = 7.0
        let rawNorm = min(max(obj.distanceM, 0.3), maxDist) / maxDist
        let normDist = sqrt(rawNorm) 
        
        let radius = maxRadius * CGFloat(normDist)
        
        let x = CGFloat(sin(angleRadians)) * radius
        let y = -CGFloat(cos(angleRadians)) * radius
        
        return CGPoint(x: x, y: y)
    }
}

struct RadarBlip: View {
    let obj: DetectedObjectDTO
    let sweepColor: Color
    
    var body: some View {
        ZStack {
            Circle()
                .fill(sweepColor)
                .frame(width: 10, height: 10)
                .shadow(color: sweepColor.opacity(0.8), radius: 6)
                .shadow(color: sweepColor.opacity(0.4), radius: 12)
            
            // Distance label for high priority
            if obj.priority.uppercased() == "HIGH" {
                Text(String(format: "%.1fm", obj.distanceM))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(sweepColor)
                    .offset(y: 14)
            }
        }
    }
}

struct RadarSweepLine: View {
    var maxRadius: CGFloat
    var sweepColor: Color
    @State private var sweep: Double = 0

    var body: some View {
        Path { p in
            p.move(to: .zero)
            p.addLine(to: CGPoint(
                x: CGFloat(sin(sweep * .pi / 180.0)) * maxRadius,
                y: -CGFloat(cos(sweep * .pi / 180.0)) * maxRadius
            ))
        }
        .stroke(
            LinearGradient(
                colors: [sweepColor.opacity(0.6), .clear],
                startPoint: .init(x: 0.5, y: 1.0),
                endPoint: .init(x: 0.5, y: 0.0)
            ),
            lineWidth: 3
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                sweep = 50
            }
        }
    }
}

struct ConeShape: Shape {
    var angle: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = rect.height
        let startAngle = Angle(degrees: 270 - (angle/2))
        let endAngle = Angle(degrees: 270 + (angle/2))
        
        p.move(to: center)
        p.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        p.closeSubpath()
        return p
    }
}
