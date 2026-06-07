import SwiftUI

/// Shared look: deep charcoal shell, single mint accent, glass surfaces.
enum VisionBridgeTheme {
    static let accent = Color(hue: 0.40, saturation: 0.55, brightness: 0.92) // soft mint
    static let accentDim = Color(hue: 0.40, saturation: 0.35, brightness: 0.55)
    static let warmAlert = Color(hue: 0.12, saturation: 0.55, brightness: 0.95)
    static let info = Color(hue: 0.55, saturation: 0.45, brightness: 0.95) // cool blue-white

    static var background: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.06, blue: 0.09),
                Color(red: 0.02, green: 0.02, blue: 0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var glassBackground: some ShapeStyle {
        .ultraThinMaterial
    }

    static var glassStroke: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.12), .white.opacity(0.03)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func premiumShadow<S: Shape>(_ shape: S) -> some View {
        shape
            .fill(.clear)
            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 12)
            .shadow(color: accent.opacity(0.04), radius: 40, x: 0, y: 0)
    }

    static let cornerL: CGFloat = 28
    static let cornerM: CGFloat = 18
    static let cornerS: CGFloat = 12
}

struct GlassPanel<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = VisionBridgeTheme.cornerM
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.04), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(VisionBridgeTheme.glassStroke, lineWidth: 1)
            }
            .background {
                VisionBridgeTheme.premiumShadow(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
