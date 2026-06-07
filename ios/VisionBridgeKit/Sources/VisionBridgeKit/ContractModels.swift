import Foundation

// MARK: - JSON contract (matches PRD + Python `src/visual_engine/contracts.py`)

public struct BBoxNorm: Codable, Equatable, Sendable {
    public var xCenterNorm: Double
    public var yCenterNorm: Double
    public var widthNorm: Double
    public var heightNorm: Double

    enum CodingKeys: String, CodingKey {
        case xCenterNorm = "x_center_norm"
        case yCenterNorm = "y_center_norm"
        case widthNorm = "width_norm"
        case heightNorm = "height_norm"
    }

    public init(
        xCenterNorm: Double,
        yCenterNorm: Double,
        widthNorm: Double,
        heightNorm: Double
    ) {
        self.xCenterNorm = xCenterNorm
        self.yCenterNorm = yCenterNorm
        self.widthNorm = widthNorm
        self.heightNorm = heightNorm
    }
}

public struct DetectedObjectDTO: Codable, Equatable, Sendable {
    public var objectId: String
    public var objectClass: String
    public var confidence: Double
    public var bbox: BBoxNorm
    public var distanceM: Double
    public var distanceConfidence: DistanceConfidence?
    public var panValue: Double
    public var velocityMps: Double
    public var priority: String

    enum CodingKeys: String, CodingKey {
        case objectId = "object_id"
        case objectClass = "class"
        case confidence
        case bbox
        case distanceM = "distance_m"
        case distanceConfidence = "distance_confidence"
        case panValue = "pan_value"
        case velocityMps = "velocity_mps"
        case priority
    }
}

public struct CameraHealthDTO: Codable, Equatable, Sendable {
    public var lensStatus: String
    public var lensLaplacianVar: Double
    public var lensAnnounce: String?

    enum CodingKeys: String, CodingKey {
        case lensStatus = "lens_status"
        case lensLaplacianVar = "lens_laplacian_var"
        case lensAnnounce = "lens_announce"
    }

    public init(lensStatus: String, lensLaplacianVar: Double, lensAnnounce: String?) {
        self.lensStatus = lensStatus
        self.lensLaplacianVar = lensLaplacianVar
        self.lensAnnounce = lensAnnounce
    }
}

public struct FramePayload: Codable, Equatable, Sendable {
    public var frameId: Int
    public var timestampMs: Int64
    public var visionDurationMs: Int
    public var objects: [DetectedObjectDTO]
    public var camera: CameraHealthDTO?

    enum CodingKeys: String, CodingKey {
        case frameId = "frame_id"
        case timestampMs = "timestamp_ms"
        case visionDurationMs = "vision_duration_ms"
        case objects
        case camera
    }

    public init(
        frameId: Int,
        timestampMs: Int64,
        visionDurationMs: Int,
        objects: [DetectedObjectDTO],
        camera: CameraHealthDTO? = nil
    ) {
        self.frameId = frameId
        self.timestampMs = timestampMs
        self.visionDurationMs = visionDurationMs
        self.objects = objects
        self.camera = camera
    }
}
