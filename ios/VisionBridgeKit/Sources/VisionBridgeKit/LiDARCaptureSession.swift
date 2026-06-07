#if canImport(ARKit)
import ARKit
import Foundation

/// ARKit-based capture session that exposes `ARFrame` with depth.
/// Use only on devices which support sceneDepth. Do not run alongside `AVCaptureSession`.
public final class LiDARCaptureSession: NSObject, ARSessionDelegate {
    private let arSession = ARSession()
    public var onFrame: ((ARFrame) -> Void)?

    public override init() {
        super.init()
    }

    public func start() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            assertionFailure("LiDARCaptureSession started on unsupported device")
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        arSession.delegate = self
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    public func stop() {
        arSession.pause()
    }

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        onFrame?(frame)
    }
}
#endif
