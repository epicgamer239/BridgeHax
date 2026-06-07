import CoreGraphics
import Foundation

/// Sentinel distance when the pinhole model cannot be applied (e.g. no measurable bbox axis) — not spoken as a real range.
public enum MonocularDistance: Sendable {
    public static let unmeasurableMeters: Double = 99.0
}

public enum MonocularAxis: String, Sendable, Codable {
    case height
    case width
    case mean
}

enum VisionGeometry {
    /// Convert Vision's normalized box (origin lower-left) to top-left / PRD-style normalized centers and sizes.
    static func prdBoxFromVisionBoundingBox(
        _ box: CGRect
    ) -> (xCenter: Double, yCenter: Double, w: Double, h: Double) {
        let x = box.origin.x
        let w = box.size.width
        let yBottom = box.origin.y
        let h = box.size.height
        let yTop = 1.0 - yBottom - h
        let cx = x + w * 0.5
        let cy = yTop + h * 0.5
        return (Double(cx), Double(cy), Double(w), Double(h))
    }

    static func panValue(xCenterNorm: Double) -> Double {
        let v = (xCenterNorm - 0.5) * 2.0
        return min(1, max(-1, v))
    }

    static func prdBboxVisibleAreaFraction(
        xCenter: Double,
        yCenter: Double,
        w: Double,
        h: Double
    ) -> Double {
        let x0 = xCenter - w * 0.5
        let x1 = xCenter + w * 0.5
        let y0 = yCenter - h * 0.5
        let y1 = yCenter + h * 0.5
        let ix0 = max(0, min(1, x0))
        let ix1 = max(0, min(1, x1))
        let iy0 = max(0, min(1, y0))
        let iy1 = max(0, min(1, y1))
        let iw = max(0, ix1 - ix0)
        let ih = max(0, iy1 - iy0)
        let aIn = iw * ih
        let aBox = max(w * h, 1e-9)
        return aIn / aBox
    }

    /// Axis-aware pinhole distance using **real** horizontal/vertical focal lengths (pixels) from `CameraIntrinsics`.
    public static func estimateMonocularDistanceM(
        widthNorm: Double,
        heightNorm: Double,
        frameWidth: Int,
        frameHeight: Int,
        intrinsics: CameraIntrinsics,
        knownHeightM: Double?,
        knownWidthM: Double?
    ) -> (meters: Double, axis: MonocularAxis) {
        let fw = max(1, Double(frameWidth))
        let fh = max(1, Double(frameHeight))
        let bboxWpx = widthNorm * fw
        let bboxHpx = heightNorm * fh
        let fX = intrinsics.focalLengthXPx
        let fY = intrinsics.focalLengthYPx
        var parts: [(Double, MonocularAxis)] = []
        if let h = knownHeightM, bboxHpx > 10 {
            parts.append(((h * fY) / bboxHpx, .height))
        }
        if let w = knownWidthM, bboxWpx > 10 {
            parts.append(((w * fX) / bboxWpx, .width))
        }
        guard !parts.isEmpty else {
            return (.nan, .height)
        }
        if parts.count == 1, let p = parts.first {
            return (applyOutputClamps(meters: p.0, widthNorm: widthNorm, heightNorm: heightNorm), p.1)
        }
        let dH = parts[0].0
        let dW = parts[1].0
        let raw: Double
        let ax: MonocularAxis
        if dH > 0, dW > 0, max(dH, dW) / min(dH, dW) < 2.0 {
            raw = (dH * dW).squareRoot()
            ax = .mean
        } else {
            raw = bboxWpx >= bboxHpx ? dW : dH
            ax = bboxWpx >= bboxHpx ? .width : .height
        }
        let m = applyOutputClamps(meters: raw, widthNorm: widthNorm, heightNorm: heightNorm)
        return (m, ax)
    }

    private static func applyOutputClamps(meters: Double, widthNorm: Double, heightNorm: Double) -> Double {
        var m = min(max(meters, 0.3), 20.0)
        if !m.isFinite { m = 0.3 }
        let fills = widthNorm > 0.6 || heightNorm > 0.6
        if fills { m = min(m, 0.5) }
        return (m * 100).rounded() / 100
    }
}
