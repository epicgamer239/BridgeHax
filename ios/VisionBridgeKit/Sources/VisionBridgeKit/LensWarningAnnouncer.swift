#if os(iOS)
import Combine
import Foundation

/// Placeholder: lens-smudge TTS is not part of the shipping app. Kept for API stability if you re-enable a lens check in `VisionConfiguration`.
@MainActor
public final class LensWarningAnnouncer: ObservableObject {
    public var minInterval: TimeInterval = 45

    public init() {}

    public func announceIfNeeded(camera: CameraHealthDTO?) {
        _ = camera
    }
}
#endif
