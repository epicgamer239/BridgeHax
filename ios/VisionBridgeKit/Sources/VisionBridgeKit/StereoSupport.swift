import Foundation
import Darwin

#if os(iOS)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Optional stereo depth helpers. **MultiCam** must not start on devices where multi-cam is unsupported.
public enum StereoDepthSupport {
    #if os(iOS)
    public static var supportsStereoDepth: Bool {
        AVCaptureMultiCamSession.isMultiCamSupported
            && AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) != nil
    }
    #else
    public static var supportsStereoDepth: Bool { false }
    #endif

    /// Baseline `Z = baseline * f / disparity` (meters). `disparity_px` is horizontal offset of the same feature in pixels.
    public static func stereoDistanceMeters(disparityPx: Double, baselineM: Double, focalLengthPx: Double) -> Double {
        guard disparityPx > 1.0 else { return .nan }
        return (baselineM * focalLengthPx) / disparityPx
    }

    /// Nominal inter-lens distance (meters). iPhone 15/16 Pro / Pro Max (wider) ≈24mm; earlier Pro / dual 1×+2× ≈12mm.
    public static func interLensBaselineMeters(machineIdentifier: String) -> Double? {
        guard machineIdentifier.hasPrefix("iPhone") else { return nil }
        if machineIdentifier.hasPrefix("iPhone16,") || machineIdentifier.hasPrefix("iPhone17,") || machineIdentifier.hasPrefix("iPhone15,") {
            return 0.024
        }
        if machineIdentifier.hasPrefix("iPhone") { return 0.012 }
        return nil
    }

    public static func currentMachineIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    /// Fuse monocular and stereo when stereo is finite; otherwise monocular. Large disagreement downweights stereo.
    public static func fusedDistanceMeters(monocular: Double, stereo: Double?) -> (meters: Double, highAgreement: Bool) {
        guard let s = stereo, s.isFinite, s > 0.1, s < 100, monocular > 0.1 else {
            return (monocular, false)
        }
        let lo = min(monocular, s)
        let hi = max(monocular, s)
        if hi / max(lo, 1e-6) > 3.0 {
            return (monocular, false)
        }
        if hi / max(lo, 1e-6) < 1.5 {
            return ((monocular + s) * 0.5, true)
        }
        return ((monocular + s) * 0.5, false)
    }
}

#if os(iOS)
/// Disables optional MultiCam stereo when the device is thermally stressed. Wire `disableStereo` to tear down a future multi-cam session.
public final class ThermalStereoGuard: @unchecked Sendable {
    public var onShouldDisableStereo: (() -> Void)?
    private var token: NSObjectProtocol?

    public init() {
        token = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let s = ProcessInfo.processInfo.thermalState
            if s == .serious || s == .critical {
                self?.onShouldDisableStereo?()
            }
        }
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
#endif
