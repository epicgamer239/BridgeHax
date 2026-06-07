import CoreVideo
import Foundation

/// Laplacian-variance sharpness (same idea as OpenCV `Laplacian(gray, CV_64F).var()`).
/// Low variance often indicates a smudged / dirty lens, heavy haze, or severe defocus.
public enum LensQualityAnalyzer {
    public static func laplacianVariance(
        pixelBuffer: CVPixelBuffer,
        maxSide: Int = 400
    ) -> Double {
        let f = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if f == kCVPixelFormatType_32BGRA {
            return laplacianVarianceBGRA(pixelBuffer: pixelBuffer, maxSide: maxSide)
        }
        // Avoid false "dirty lens" warnings when we cannot run the fast BGRA path.
        return 1_000_000
    }

    private static func laplacianVarianceBGRA(
        pixelBuffer: CVPixelBuffer,
        maxSide: Int
    ) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let src = base.assumingMemoryBound(to: UInt8.self)
        let scale = min(1.0, Double(maxSide) / Double(max(w, h)))
        let nw = max(2, Int(Double(w) * scale))
        let nh = max(2, Int(Double(h) * scale))
        var gray = [Double](repeating: 0, count: nw * nh)
        for y in 0..<nh {
            let sy = min(h - 1, Int(Double(y) * Double(h) / Double(nh)))
            for x in 0..<nw {
                let sx = min(w - 1, Int(Double(x) * Double(w) / Double(nw)))
                let o = sy * rowBytes + sx * 4
                let b = Double(src[o])
                let g = Double(src[o + 1])
                let r = Double(src[o + 2])
                gray[y * nw + x] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }
        return laplacianVarianceGray2D(width: nw, height: nh, gray: &gray)
    }

    /// OpenCV Laplacian ksize=1: [[0,1,0],[1,-4,1],[0,1,0]]
    private static func laplacianVarianceGray2D(
        width: Int,
        height: Int,
        gray: inout [Double]
    ) -> Double {
        if width < 3 || height < 3 { return 0 }
        var lap = [Double](repeating: 0, count: width * height)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let c = gray[i]
                let t = gray[i - width]
                let b = gray[i + width]
                let l = gray[i - 1]
                let r = gray[i + 1]
                lap[i] = t + b + l + r - 4 * c
            }
        }
        var sum = 0.0
        var sumSq = 0.0
        var n = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let v = lap[y * width + x]
                sum += v
                sumSq += v * v
                n += 1
            }
        }
        guard n > 0 else { return 0 }
        let mean = sum / Double(n)
        return max(0, sumSq / Double(n) - mean * mean)
    }
}

/// PRD-aligned camera health block + consecutive-frame hysteresis.
public final class LensStreakState {
    private var streak: Int = 0

    public init() {}

    public func update(
        lapVar: Double,
        config: VisionConfiguration
    ) -> CameraHealthDTO {
        guard config.enableLensCheck else {
            return CameraHealthDTO(
                lensStatus: "ok",
                lensLaplacianVar: 0,
                lensAnnounce: nil
            )
        }
        if lapVar < config.lensLaplacianThreshold {
            streak += 1
        } else {
            streak = 0
        }
        let warn = streak >= config.lensWarnConsecutive
        let st = warn ? "warning" : "ok"
        let ann = warn ? config.lensAnnouncementText : nil
        return CameraHealthDTO(
            lensStatus: st,
            lensLaplacianVar: (lapVar * 100).rounded() / 100,
            lensAnnounce: ann
        )
    }

    public func reset() {
        streak = 0
    }
}
