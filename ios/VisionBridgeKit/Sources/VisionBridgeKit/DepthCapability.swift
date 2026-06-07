import Foundation
#if canImport(ARKit)
import ARKit
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Call once at app launch. Result is immutable for the device lifetime.
public enum DepthCapability {
    case lidar
    case dualCamera
    case monocularOnly
}

public func detectDepthCapability() -> DepthCapability {
    #if canImport(ARKit)
    if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
        return .lidar
    }
    #endif
    #if os(iOS)
    if AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) != nil {
        return .dualCamera
    }
    #endif
    return .monocularOnly
}
