#if canImport(ARKit)
import ARKit
import Foundation

public struct LiDARSample {
    public let distanceM: Float
    public let confidence: DepthConfidence
    public let isValid: Bool

    public enum DepthConfidence: UInt8 {
        case low = 0, medium = 1, high = 2
    }

    public init(distanceM: Float, confidence: DepthConfidence, isValid: Bool) {
        self.distanceM = distanceM
        self.confidence = confidence
        self.isValid = isValid
    }
}

/// Sample smoothedSceneDepth at the center region of a normalized bbox.
public func sampleDepth(from frame: ARFrame, bbox: CGRect) -> LiDARSample {
    guard let depthData = frame.smoothedSceneDepth else {
        return LiDARSample(distanceM: 0, confidence: .low, isValid: false)
    }
    // `depthMap` / `confidenceMap` are `CVPixelBuffer` on some SDKs and optional on others; promote to `CVPixelBuffer?` uniformly.
    let depthMapBox: CVPixelBuffer? = depthData.depthMap
    let confMapBox: CVPixelBuffer? = depthData.confidenceMap
    guard let depthMap = depthMapBox, let confMap = confMapBox else {
        return LiDARSample(distanceM: 0, confidence: .low, isValid: false)
    }

    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    CVPixelBufferLockBaseAddress(confMap, .readOnly)
    defer {
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        CVPixelBufferUnlockBaseAddress(confMap, .readOnly)
    }

    let dW = CVPixelBufferGetWidth(depthMap)
    let dH = CVPixelBufferGetHeight(depthMap)

    guard let depthPtr = CVPixelBufferGetBaseAddress(depthMap),
          let confPtr = CVPixelBufferGetBaseAddress(confMap) else {
        return LiDARSample(distanceM: 0, confidence: .low, isValid: false)
    }

    let depthFloats = depthPtr.bindMemory(to: Float32.self, capacity: dW * dH)
    let confBytes = confPtr.bindMemory(to: UInt8.self, capacity: dW * dH)

    // Sample a 3x3 grid across the center third of the bbox for robustness
    let sampleOffsets: [(Double, Double)] = [
        (0.33, 0.33), (0.50, 0.33), (0.67, 0.33),
        (0.33, 0.50), (0.50, 0.50), (0.67, 0.50),
        (0.33, 0.67), (0.50, 0.67), (0.67, 0.67),
    ]

    var validDepths: [Float] = []
    var minConf: UInt8 = 2

    for (ox, oy) in sampleOffsets {
        let px = Int((bbox.minX + bbox.width * ox) * Double(dW))
        let py = Int((bbox.minY + bbox.height * oy) * Double(dH))
        guard px >= 0, px < dW, py >= 0, py < dH else { continue }

        let idx = py * dW + px
        let d = depthFloats[idx]
        let c = confBytes[idx]

        guard d.isFinite, d > 0.1, d <= 5.0 else { continue }
        validDepths.append(d)
        if c < minConf { minConf = c }
    }

    guard validDepths.count >= 3 else {
        return LiDARSample(distanceM: 0, confidence: .low, isValid: false)
    }

    validDepths.sort()
    let median = validDepths[validDepths.count / 2]
    let conf = LiDARSample.DepthConfidence(rawValue: minConf) ?? .low
    return LiDARSample(distanceM: median, confidence: conf, isValid: true)
}

extension LiDARSample {
    public var distanceConfidence: DistanceConfidence {
        guard isValid else { return .unavailable }
        switch confidence {
        case .high:
            return distanceM <= 5.0 ? .high : .low
        case .medium:
            return distanceM <= 3.0 ? .high : .medium
        case .low:
            return .low
        }
    }
}
#endif
