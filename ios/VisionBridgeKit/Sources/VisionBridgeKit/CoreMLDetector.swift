import CoreML
import Foundation
import Vision

public enum ModelLoadError: Error {
    case fileNotFound(String)
    case modelLoadFailed(Error)
}

/// Wraps a CoreML YOLO (Ultralytics export with NMS) for Vision. Prefer an export with `nms=True` so
/// `VNRecognizedObjectObservation` is produced.
public final class CoreMLDetector: @unchecked Sendable {
    public let config: VisionConfiguration
    private let visionModel: VNCoreMLModel
    private var cachedRequest: VNCoreMLRequest?

    public init(modelURL: URL, config: VisionConfiguration = .default) throws {
        self.config = config
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all // Priority to ANE (Apple Neural Engine)
            config.allowLowPrecisionAccumulationOnGPU = true
            
            let m = try MLModel(contentsOf: modelURL, configuration: config)
            self.visionModel = try VNCoreMLModel(for: m)
        } catch {
            throw ModelLoadError.modelLoadFailed(error)
        }
    }

    /// Bundle resource name without extension, e.g. `yolov8m-oiv7` for `yolov8m-oiv7.mlpackage`.
    public convenience init(modelResourceName: String, bundle: Bundle, config: VisionConfiguration = .default) throws {
        var url = bundle.url(forResource: modelResourceName, withExtension: "mlmodelc")
        if url == nil {
            url = bundle.url(forResource: modelResourceName, withExtension: "mlpackage")
        }
        guard let u = url else {
            throw ModelLoadError.fileNotFound(modelResourceName)
        }
        try self.init(modelURL: u, config: config)
    }

    public func makeRequest(
        handler: @escaping VNRequestCompletionHandler
    ) -> VNCoreMLRequest {
        if let cached = cachedRequest {
            return cached
        }
        let r = VNCoreMLRequest(model: visionModel, completionHandler: handler)
        r.imageCropAndScaleOption = .scaleFill
        r.preferBackgroundProcessing = true
        self.cachedRequest = r
        return r
    }

    func buildObservations(
        from request: VNRequest,
        error: (any Error)?,
        imageWidth: Int,
        imageHeight: Int,
        intrinsics: CameraIntrinsics
    ) -> [RawDetection] {
        if let error {
            #if DEBUG
            print("VisionBridgeKit CoreML: \(error.localizedDescription)")
            #endif
            return []
        }
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            return []
        }

        var out: [RawDetection] = []
        for obs in results {
            guard let top = obs.labels.first else { continue }
            let conf = top.confidence
            let rawName = labelString(from: top.identifier)
            let t = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard config.targetClassNames.contains(t) else { continue }
            guard conf >= config.confidenceThreshold(for: t) else { continue }

            let (xc, yc, w, h) = VisionGeometry.prdBoxFromVisionBoundingBox(obs.boundingBox)
            let visFrac = VisionGeometry.prdBboxVisibleAreaFraction(
                xCenter: xc,
                yCenter: yc,
                w: w,
                h: h
            )
            guard visFrac >= config.minBboxAreaFractionInFrame else { continue }
            let areaNorm = w * h
            guard areaNorm >= config.minBoxAreaFraction(for: t) else { continue }

            let (dRaw, _) = VisionGeometry.estimateMonocularDistanceM(
                widthNorm: w,
                heightNorm: h,
                frameWidth: imageWidth,
                frameHeight: imageHeight,
                intrinsics: intrinsics,
                knownHeightM: config.knownHeightMeters(for: t),
                knownWidthM: config.knownWidthMeters(for: t)
            )
            // Unmeasurable distance: keep finite sentinel so tracking priority does not treat "unknown" as 0m (high-priority).
            let dist = dRaw.isFinite && dRaw > 0.05 ? dRaw : MonocularDistance.unmeasurableMeters
            let pan = VisionGeometry.panValue(xCenterNorm: xc)
            out.append(
                RawDetection(
                    className: t,
                    confidence: Double(conf),
                    xCenterNorm: xc,
                    yCenterNorm: yc,
                    widthNorm: w,
                    heightNorm: h,
                    distanceM: dist,
                    panValue: pan
                )
            )
        }

        // Apply strict Non-Maximum Suppression (NMS) to eliminate duplicate bounding boxes
        // that YOLO sometimes produces around the exact same physical object.
        return applyNMS(out, iouThreshold: 0.40)
    }

    /// Custom IoU-based NMS for Swift (Vision does its own but often leaks duplicates)
    private func applyNMS(_ detections: [RawDetection], iouThreshold: Double) -> [RawDetection] {
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [RawDetection] = []
        var suppressed = Set<Int>()

        for i in 0..<sorted.count {
            if suppressed.contains(i) { continue }
            let base = sorted[i]
            kept.append(base)

            for j in (i + 1)..<sorted.count {
                if suppressed.contains(j) { continue }
                if iou(base, sorted[j]) > iouThreshold {
                    suppressed.insert(j)
                }
            }
        }
        return kept
    }

    private func iou(_ a: RawDetection, _ b: RawDetection) -> Double {
        let aL = a.xCenterNorm - a.widthNorm / 2
        let aR = a.xCenterNorm + a.widthNorm / 2
        let aT = a.yCenterNorm - a.heightNorm / 2
        let aB = a.yCenterNorm + a.heightNorm / 2

        let bL = b.xCenterNorm - b.widthNorm / 2
        let bR = b.xCenterNorm + b.widthNorm / 2
        let bT = b.yCenterNorm - b.heightNorm / 2
        let bB = b.yCenterNorm + b.heightNorm / 2

        let iL = max(aL, bL)
        let iR = min(aR, bR)
        let iT = max(aT, bT)
        let iB = min(aB, bB)

        let iW = max(0, iR - iL)
        let iH = max(0, iB - iT)
        let intersection = iW * iH
        let union = (a.widthNorm * a.heightNorm) + (b.widthNorm * b.heightNorm) - intersection
        return intersection / union
    }

    private func labelString(from identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = Int(trimmed), i >= 0, i < OpenImagesV7Mapping.classNames.count {
            return OpenImagesV7Mapping.classNames[i].lowercased()
        }
        return trimmed.lowercased()
    }
}
