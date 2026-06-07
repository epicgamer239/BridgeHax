import CoreGraphics
import Foundation

#if canImport(CoreMedia)
import CoreMedia
#endif
#if os(iOS)
import AVFoundation
#endif

/// Per-frame camera parameters for pinhole distance. **Production:** build from `AVCaptureDevice` + sample buffer
/// (intrinsic matrix preferred; else `activeFormat.videoFieldOfView`). Do not use hardcoded FOV in app code for distance.
public struct CameraIntrinsics: Sendable, Equatable {
    /// Horizontal focal length in pixels (maps bbox width in pixels).
    public var focalLengthXPx: Double
    /// Vertical focal length in pixels (maps bbox height in pixels).
    public var focalLengthYPx: Double
    public var frameWidth: Int
    public var frameHeight: Int
    /// Metadata only — do not multiply into `f`; FOV or matrix already match the active lens.
    public var lensFactor: Double
    public var horizontalFieldOfViewDegrees: Double
    public var didUseSampleBufferMatrix: Bool

    public init(
        focalLengthXPx: Double,
        focalLengthYPx: Double,
        frameWidth: Int,
        frameHeight: Int,
        lensFactor: Double,
        horizontalFieldOfViewDegrees: Double,
        didUseSampleBufferMatrix: Bool
    ) {
        self.focalLengthXPx = focalLengthXPx
        self.focalLengthYPx = focalLengthYPx
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.lensFactor = lensFactor
        self.horizontalFieldOfViewDegrees = horizontalFieldOfViewDegrees
        self.didUseSampleBufferMatrix = didUseSampleBufferMatrix
    }
}

#if os(iOS)
public enum CameraIntrinsicsReader {
    /// Read intrinsics from the active camera. Prefer the **intrinsic matrix** on `CMSampleBuffer` when present; otherwise
    /// use `activeFormat.videoFieldOfView` (horizontal, degrees) to derive `f_x = (W/2) / tan(hFOV/2)` and
    /// `f_y` from a consistent pinhole (square-ish pixels) using vertical FOV from aspect.
    public static func read(
        device: AVCaptureDevice,
        frameWidth: Int,
        frameHeight: Int,
        sampleBuffer: CMSampleBuffer?
    ) -> CameraIntrinsics {
        let w = max(1, frameWidth)
        let h = max(1, frameHeight)
        let lens: Double = device.deviceType.lensFactor
        if let sampleBuffer, let fxFy = Self.focalFromIntrinsicAttachment(sampleBuffer) {
            let (fx, fy) = fxFy
            let hFov = 2.0 * atan(Double(w) / (2.0 * max(fx, 0.1))) * 180.0 / .pi
            return CameraIntrinsics(
                focalLengthXPx: min(max(fx, 10), 20_000),
                focalLengthYPx: min(max(fy, 10), 20_000),
                frameWidth: w,
                frameHeight: h,
                lensFactor: lens,
                horizontalFieldOfViewDegrees: hFov,
                didUseSampleBufferMatrix: true
            )
        }
        return Self.readFromFieldOfView(device: device, frameWidth: w, frameHeight: h, lens: lens)
    }

    private static func readFromFieldOfView(
        device: AVCaptureDevice,
        frameWidth: Int,
        frameHeight: Int,
        lens: Double
    ) -> CameraIntrinsics {
        let w = Double(frameWidth)
        let h = Double(frameHeight)
        let hFovRad = Double(device.activeFormat.videoFieldOfView) * .pi / 180.0
        let fX = (w / 2.0) / max(tan(hFovRad / 2.0), 0.01)
        let vFovRad = 2.0 * atan((h / w) * tan(hFovRad / 2.0))
        let fY = (h / 2.0) / max(tan(vFovRad / 2.0), 0.01)
        return CameraIntrinsics(
            focalLengthXPx: min(max(fX, 10), 20_000),
            focalLengthYPx: min(max(fY, 10), 20_000),
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            lensFactor: lens,
            horizontalFieldOfViewDegrees: Double(device.activeFormat.videoFieldOfView),
            didUseSampleBufferMatrix: false
        )
    }

    /// Row-major 3×3 K: indices 0 and 4 are fx and fy in typical iPhone camera matrices.
    private static func dataFromSampleBufferAttachment(_ value: Any) -> Data? {
        if let d = value as? Data { return d }
        if let d = value as? NSData { return d as Data }
        let cf = value as CFTypeRef
        guard CFGetTypeID(cf) == CFDataGetTypeID() else { return nil }
        return (cf as! CFData) as Data
    }

    private static func focalFromIntrinsicAttachment(_ sampleBuffer: CMSampleBuffer) -> (Double, Double)? {
        let key = kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix
        guard let att = CMGetAttachment(sampleBuffer, key: key, attachmentModeOut: nil) else { return nil }
        guard let d = dataFromSampleBufferAttachment(att), d.count >= 9 * MemoryLayout<Float32>.size else { return nil }
        let floats: [Float] = d.withUnsafeBytes { buf in
            Array(buf.bindMemory(to: Float32.self).prefix(9).map { Float($0) })
        }
        let fx = Double(floats[0])
        let fy = Double(floats[4])
        guard fx > 1, fx < 20_000, fy > 1, fy < 20_000 else { return nil }
        return (fx, fy)
    }
}
#endif

#if os(iOS)
extension AVCaptureDevice.DeviceType {
    public var lensFactor: Double {
        switch self {
        case .builtInUltraWideCamera: return 0.5
        case .builtInWideAngleCamera: return 1.0
        case .builtInTelephotoCamera: return 2.0
        default: return 1.0
        }
    }
}
#endif

#if canImport(ARKit)
import ARKit

@available(iOS 13.0, *)
extension CameraIntrinsicsReader {
    public static func read(from arCamera: ARCamera) -> CameraIntrinsics {
        let w = Int(arCamera.imageResolution.width)
        let h = Int(arCamera.imageResolution.height)
        let k = arCamera.intrinsics
        let fx = Double(k.columns.0.x)
        let fy = Double(k.columns.1.y)
        let hFov = 2.0 * atan(Double(w) / (2.0 * max(fx, 0.0001))) * 180.0 / .pi
        return CameraIntrinsics(
            focalLengthXPx: min(max(fx, 10), 20_000),
            focalLengthYPx: min(max(fy, 10), 20_000),
            frameWidth: w,
            frameHeight: h,
            lensFactor: 1.0,
            horizontalFieldOfViewDegrees: hFov,
            didUseSampleBufferMatrix: true
        )
    }
}
#endif

#if os(iOS)
extension AVCaptureDevice {
    public var deviceTypeLensFactor: Double { deviceType.lensFactor }
}
#endif

extension CameraIntrinsics {
    /// **Non-production** (unit tests, macOS `swift test`, scripts). Real iPhone builds must use `CameraIntrinsicsReader.read`.
    public static func evalOnlyFromFrameDimensions(
        width: Int,
        height: Int,
        horizontalFOVDeg: Double = 63
    ) -> CameraIntrinsics {
        let w = Double(max(1, width))
        let h = Double(max(1, height))
        let hFovRad = horizontalFOVDeg * .pi / 180.0
        let fX = (w / 2.0) / max(tan(hFovRad / 2.0), 0.01)
        let vFovRad = 2.0 * atan((h / w) * tan(hFovRad / 2.0))
        let fY = (h / 2.0) / max(tan(vFovRad / 2.0), 0.01)
        return CameraIntrinsics(
            focalLengthXPx: fX,
            focalLengthYPx: fY,
            frameWidth: max(1, width),
            frameHeight: max(1, height),
            lensFactor: 1.0,
            horizontalFieldOfViewDegrees: horizontalFOVDeg,
            didUseSampleBufferMatrix: false
        )
    }
}
