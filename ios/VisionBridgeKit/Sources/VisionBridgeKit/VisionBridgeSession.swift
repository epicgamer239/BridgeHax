import Combine
import CoreVideo
import ImageIO
#if canImport(ARKit)
import ARKit
#endif

/// SwiftUI-friendly wrapper: publish the latest `FramePayload` on the main actor.
@MainActor
public final class VisionBridgeSession: ObservableObject {
    @Published public private(set) var lastPayload: FramePayload?
    /// Safe to use from the camera buffer queue; vision work is off the main actor inside `OnDeviceVisionEngine`.
    public nonisolated let engine: OnDeviceVisionEngine
    #if os(iOS)
    public let lensAnnouncer: LensWarningAnnouncer?
    #endif

    public init(
        engine: OnDeviceVisionEngine,
        enableLensSpeech: Bool = false
    ) {
        self.engine = engine
        #if os(iOS)
        self.lensAnnouncer = enableLensSpeech ? LensWarningAnnouncer() : nil
        #endif
    }

    /// Called from the camera `AVCapture` buffer queue. Does not hop through `MainActor` (previous design scheduled every frame on main and caused UI hitches).
    nonisolated public func ingest(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        intrinsics: CameraIntrinsics? = nil
    ) {
        engine.process(pixelBuffer: pixelBuffer, orientation: orientation, intrinsics: intrinsics) { [weak self] payload in
            guard let self, let payload else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                #if os(iOS)
                self.lensAnnouncer?.announceIfNeeded(camera: payload.camera)
                #endif
                self.lastPayload = payload
            }
        }
    }

#if canImport(ARKit)
    /// ARKit ingestion: pass the ARFrame captured by `LiDARCaptureSession`.
    nonisolated public func ingest(frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        let orientation: CGImagePropertyOrientation = .right
        #if os(iOS)
        let intr = CameraIntrinsicsReader.read(from: frame.camera)
        #else
        let intr: CameraIntrinsics? = nil
        #endif
        engine.process(pixelBuffer: pixelBuffer, orientation: orientation, intrinsics: intr, arFrame: frame) { [weak self] payload in
            guard let self, let payload else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                #if os(iOS)
                self.lensAnnouncer?.announceIfNeeded(camera: payload.camera)
                #endif
                self.lastPayload = payload
            }
        }
    }
#endif

    public func resetTracking() {
        engine.resetTracker()
    }

    public func clearPayload() {
        lastPayload = nil
    }
}
