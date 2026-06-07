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
            "person", "car", "bicycle", "motorcycle", "truck", "bus",
            "dog", "cat", "chair", "couch",
            "kitchen & dining room table", "plant", "backpack", "handbag", "suitcase",
            "mobile phone", "laptop",
            "television", "computer keyboard", "computer mouse", "remote control",
            "bottle", "coffee cup", "umbrella", "traffic light", "fire hydrant",
            "stop sign", "bench", "stairs", "waste container", "computer monitor",
            "building",
        ]),
        knownHeightsM: [
            "person": 1.70,
            "car": 1.50,
            "truck": 3.20,
            "bus": 3.50,
            "motorcycle": 1.20,
            "bicycle": 1.10,
            "dog": 0.50,
            "cat": 0.30,
            "chair": 0.90,
            "couch": 0.90,
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
            "suitcase": 0.65,
            "traffic light": 0.90,
            "stop sign": 0.75,
            "fire hydrant": 0.60,
            "bench": 0.90,
            "umbrella": 1.00,
            "plant": 0.60,
            "handbag": 0.30,
            "stairs": 0.25,
            "waste container": 0.90,
            "computer monitor": 0.45,
        ],
        knownWidthsM: [
            "person": 0.50,
            "car": 1.80,
            "truck": 2.40,
            "bus": 2.50,
            "motorcycle": 1.00,
            "bicycle": 1.70,
            "couch": 1.80,
            "kitchen & dining room table": 1.20,
            "laptop": 0.32,
            "television": 0.90,
            "computer keyboard": 0.45,
            "computer mouse": 0.10,
            "remote control": 0.08,
            "dog": 0.60,
            "cat": 0.40,
            "bench": 1.50,
            "suitcase": 0.45,
            "chair": 0.55,
            "plant": 0.45,
            "backpack": 0.40,
            "handbag": 0.40,
            "mobile phone": 0.08,
            "bottle": 0.08,
            "coffee cup": 0.10,
            "umbrella": 0.90,
            "traffic light": 0.40,
            "fire hydrant": 0.45,
            "stop sign": 0.60,
            "waste container": 0.45,
            "computer monitor": 0.55,
            "stairs": 1.20,
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
