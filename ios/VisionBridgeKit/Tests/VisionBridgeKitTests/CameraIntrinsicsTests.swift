import XCTest
@testable import VisionBridgeKit

final class CameraIntrinsicsTests: XCTestCase {
    /// Eval / tests only: 63° HFOV on 1920-wide frame should match the pinhole formula (not a device value).
    func testFocalFromHorizontalFOV_1920Wide() {
        let r = CameraIntrinsics.evalOnlyFromFrameDimensions(width: 1_920, height: 1_080, horizontalFOVDeg: 63)
        let hFov = 63.0 * Double.pi / 180.0
        let expected = (1_920.0 / 2.0) / tan(hFov / 2.0)
        XCTAssertEqual(r.focalLengthXPx, expected, accuracy: 1.0)
    }
}
