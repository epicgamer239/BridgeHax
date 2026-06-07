import XCTest
@testable import VisionBridgeKit

final class SpeechSupportTests: XCTestCase {
    func testPhraseBuilderConfidenceTemplates() {
        let b = PhraseBuilder()
        let high = b.phrase(
            objectClass: "person",
            panValue: 0.0,
            distance: DistanceAssessment(meters: 2.1, confidence: .high, wasDampened: false),
            units: "metric"
        )
        XCTAssertTrue(high.contains("about"))

        let med = b.phrase(
            objectClass: "person",
            panValue: 0.0,
            distance: DistanceAssessment(meters: 2.1, confidence: .medium, wasDampened: false),
            units: "metric"
        )
        XCTAssertTrue(med.contains("roughly"))

        let low = b.phrase(
            objectClass: "person",
            panValue: 0.0,
            distance: DistanceAssessment(meters: 4.2, confidence: .low, wasDampened: false),
            units: "metric"
        )
        XCTAssertTrue(low.contains("farther ahead") || low.contains("nearby"))

        let unavailable = b.phrase(
            objectClass: "person",
            panValue: 0.0,
            distance: DistanceAssessment(meters: nil, confidence: .unavailable, wasDampened: false),
            units: "metric"
        )
        XCTAssertTrue(unavailable.contains("detected"))
    }

    func testSchedulerSceneFlushKeepsHighAndDropsNormal() {
        let s = SpeechScheduler(capPerTier: 100)
        for i in 0..<20 {
            s.enqueue("n\(i)", priority: .normal, ttl: 20, objectID: "n\(i)")
        }
        s.enqueue("high", priority: .high, ttl: 20, objectID: "h1")
        s.sceneDropFlush(previousCount: 20, newCount: 6) // >50% drop
        XCTAssertLessThanOrEqual(s.currentDepth, 2)
    }

    func testJumpDampening_EMA() {
        var a = DistanceConfidenceAssessor(alpha: 0.3)
        let b = BBoxNorm(xCenterNorm: 0.5, yCenterNorm: 0.5, widthNorm: 0.2, heightNorm: 0.3)
        _ = a.assess(
            DistanceFrameSample(objectID: "p1", className: "person", bbox: b, rawDistanceM: 1.0, timestamp: Date()),
            hasKnownPhysicalSize: true
        )
        let next = a.assess(
            DistanceFrameSample(
                objectID: "p1",
                className: "person",
                bbox: b,
                rawDistanceM: 3.0,
                timestamp: Date().addingTimeInterval(0.1)
            ),
            hasKnownPhysicalSize: true
        )
        XCTAssertEqual(next.confidence, .low)
        XCTAssertTrue(next.wasDampened)
        // EMA: 0.3 * 3 + 0.7 * 1 = 1.6
        XCTAssertEqual(next.meters ?? 0, 1.6, accuracy: 0.01)
    }

    func testNoKnownSize_Unavailable() {
        var a = DistanceConfidenceAssessor(alpha: 0.3)
        let b = BBoxNorm(xCenterNorm: 0.5, yCenterNorm: 0.5, widthNorm: 0.1, heightNorm: 0.1)
        let o = a.assess(
            DistanceFrameSample(objectID: "s1", className: "scissors", bbox: b, rawDistanceM: 1.0, timestamp: Date()),
            hasKnownPhysicalSize: false
        )
        XCTAssertEqual(o.confidence, .unavailable)
        let phrase = PhraseBuilder().phrase(
            objectClass: "scissors",
            panValue: 0.0,
            distance: o,
            units: "metric"
        )
        XCTAssertTrue(phrase.contains("detected"))
        XCTAssertFalse(phrase.contains("1 meter") || phrase.contains("meter"))
    }
}
