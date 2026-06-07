import XCTest
@testable import VisionBridgeKit

final class VisionGeometryTests: XCTestCase {
    private func i(_ w: Int, _ h: Int) -> CameraIntrinsics {
        CameraIntrinsics.evalOnlyFromFrameDimensions(width: w, height: h, horizontalFOVDeg: 63)
    }

    /// Landscape laptop: width-dominated bbox; distance should be ~arm’s length, not many meters.
    func testLaptopWide_ReasonableRange() {
        let intr = i(1_920, 1_080)
        let (d, ax) = VisionGeometry.estimateMonocularDistanceM(
            widthNorm: 0.65,
            heightNorm: 0.2,
            frameWidth: 1_920,
            frameHeight: 1_080,
            intrinsics: intr,
            knownHeightM: VisionConfiguration.default.knownHeightsM["laptop"],
            knownWidthM: VisionConfiguration.default.knownWidthsM["laptop"]
        )
        XCTAssertEqual(ax, .width)
        XCTAssertGreaterThanOrEqual(d, 0.15)
        XCTAssertLessThanOrEqual(d, 0.4)
    }

    func testPersonTall_ReasonableRange() {
        let intr = i(1_920, 1_080)
        // Bbox width in px < 10 so only height-based size is used (tall, narrow "person" crop).
        let (d, ax) = VisionGeometry.estimateMonocularDistanceM(
            widthNorm: 0.002,
            heightNorm: 0.45,
            frameWidth: 1_920,
            frameHeight: 1_080,
            intrinsics: intr,
            knownHeightM: VisionConfiguration.default.knownHeightsM["person"],
            knownWidthM: VisionConfiguration.default.knownWidthsM["person"]
        )
        XCTAssertEqual(ax, .height)
        XCTAssertGreaterThanOrEqual(d, 0.5)
        XCTAssertLessThanOrEqual(d, 8.0)
    }

    func testFillsFrameClamp() {
        let intr = i(1_920, 1_080)
        let (d, _) = VisionGeometry.estimateMonocularDistanceM(
            widthNorm: 0.7,
            heightNorm: 0.15,
            frameWidth: 1_920,
            frameHeight: 1_080,
            intrinsics: intr,
            knownHeightM: VisionConfiguration.default.knownHeightsM["laptop"],
            knownWidthM: VisionConfiguration.default.knownWidthsM["laptop"]
        )
        XCTAssertLessThanOrEqual(d, 0.5)
    }
}
