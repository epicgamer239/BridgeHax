import Foundation

/// Tuning for on-device YOLO + monocular range. **Distance:** iPhone only — `CameraIntrinsics` from `AVCaptureDevice`
/// supplies focal lengths; there is no fixed `f` in this struct.
public struct VisionConfiguration: Sendable {
    public var confidenceThreshold: Float
    public var minBboxAreaFractionInFrame: Double
    /// Per-class confidence overrides for noisy classes. Key must be lowercased class key.
    public var classConfidenceThresholds: [String: Float]
    /// Per-class minimum bbox area (w*h in normalized frame units) for tiny false-positive-prone classes.
    public var minBoxAreaFractionByClass: [String: Double]
    public var targetClassNames: Set<String>
    public var knownHeightsM: [String: Double]
    public var knownWidthsM: [String: Double]
    public var minEmitInterval: TimeInterval
    public var highPriorityDistanceM: Double
    public var enableLensCheck: Bool
    public var lensLaplacianThreshold: Double
    public var lensWarnConsecutive: Int
    public var lensCheckMaxSide: Int
    public var lensAnnouncementText: String

    public static let `default` = VisionConfiguration(
        confidenceThreshold: 0.58,
        minBboxAreaFractionInFrame: 0.7,
        classConfidenceThresholds: [
            "mobile phone": 0.86,
            "remote control": 0.80,
            "computer mouse": 0.80,
            "computer keyboard": 0.74,
            "coffee cup": 0.72,
        ],
        minBoxAreaFractionByClass: [
            "mobile phone": 0.0080,
            "remote control": 0.0100,
            "computer mouse": 0.0070,
            "coffee cup": 0.0060,
        ],
        targetClassNames: Set([
            "person", "chair", "kitchen & dining room table", "backpack",
            "mobile phone", "laptop", "television", "computer keyboard", "computer mouse", "remote control",
            "bottle", "coffee cup", "stairs", "waste container", "computer monitor",
            "building", "door",
        ]),
        knownHeightsM: [
            "person": 1.70,
            "chair": 0.90,
            "kitchen & dining room table": 0.75,
            "laptop": 0.24,
            "television": 0.50,
            "computer keyboard": 0.05,
            "computer mouse": 0.04,
            "remote control": 0.03,
            "mobile phone": 0.15,
            "bottle": 0.25,
            "coffee cup": 0.12,
            "backpack": 0.55,
            "stairs": 0.25,
            "waste container": 0.90,
            "computer monitor": 0.45,
            "door": 2.00,
        ],
        knownWidthsM: [
            "person": 0.50,
            "kitchen & dining room table": 1.20,
            "laptop": 0.32,
            "television": 0.90,
            "computer keyboard": 0.45,
            "computer mouse": 0.10,
            "remote control": 0.08,
            "chair": 0.55,
            "backpack": 0.40,
            "mobile phone": 0.08,
            "bottle": 0.08,
            "coffee cup": 0.10,
            "waste container": 0.45,
            "computer monitor": 0.55,
            "stairs": 1.20,
            "door": 0.90,
        ],
        minEmitInterval: 1.0 / 15.0,
        highPriorityDistanceM: 3.0,
        enableLensCheck: false,
        lensLaplacianThreshold: 100,
        lensWarnConsecutive: 4,
        lensCheckMaxSide: 400,
        lensAnnouncementText: ""
    )

    public init(
        confidenceThreshold: Float,
        minBboxAreaFractionInFrame: Double = 0.7,
        classConfidenceThresholds: [String: Float] = VisionConfiguration.default.classConfidenceThresholds,
        minBoxAreaFractionByClass: [String: Double] = VisionConfiguration.default.minBoxAreaFractionByClass,
        targetClassNames: Set<String>,
        knownHeightsM: [String: Double],
        knownWidthsM: [String: Double]? = nil,
        minEmitInterval: TimeInterval,
        highPriorityDistanceM: Double,
        enableLensCheck: Bool = false,
        lensLaplacianThreshold: Double = 100,
        lensWarnConsecutive: Int = 4,
        lensCheckMaxSide: Int = 400,
        lensAnnouncementText: String = ""
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.minBboxAreaFractionInFrame = minBboxAreaFractionInFrame
        self.classConfidenceThresholds = classConfidenceThresholds
        self.minBoxAreaFractionByClass = minBoxAreaFractionByClass
        self.targetClassNames = targetClassNames
        self.knownHeightsM = knownHeightsM
        self.knownWidthsM = knownWidthsM ?? VisionConfiguration.default.knownWidthsM
        self.minEmitInterval = minEmitInterval
        self.highPriorityDistanceM = highPriorityDistanceM
        self.enableLensCheck = enableLensCheck
        self.lensLaplacianThreshold = lensLaplacianThreshold
        self.lensWarnConsecutive = lensWarnConsecutive
        self.lensCheckMaxSide = lensCheckMaxSide
        self.lensAnnouncementText = lensAnnouncementText
    }

    public func knownHeightMeters(for className: String) -> Double? {
        let k = className.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return knownHeightsM[k]
    }

    public func knownWidthMeters(for className: String) -> Double? {
        let k = className.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return knownWidthsM[k]
    }

    public func hasKnownPhysicalSize(for className: String) -> Bool {
        knownHeightMeters(for: className) != nil || knownWidthMeters(for: className) != nil
    }

    public func confidenceThreshold(for className: String) -> Float {
        let k = className.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return classConfidenceThresholds[k] ?? confidenceThreshold
    }

    public func minBoxAreaFraction(for className: String) -> Double {
        let k = className.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return minBoxAreaFractionByClass[k] ?? 0.0
    }
}
