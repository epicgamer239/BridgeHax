import CoreVideo
import Foundation
import ImageIO
import QuartzCore
import Vision
#if canImport(ARKit)
import ARKit
#endif

/// Runs YOLO (CoreML) on-device, maps to PRD `FramePayload`, with drops + ~15Hz emit cap.
public final class OnDeviceVisionEngine: @unchecked Sendable {
    public let config: VisionConfiguration
    private let detector: CoreMLDetector
    private var tracker: ObjectTracker
    private let workQueue: DispatchQueue
    private let stateLock = NSLock()
    private var frameId: Int = 0
    private var inFlight: Bool = false
    private var lastEmitTime: TimeInterval = 0
    private let lensState = LensStreakState()
    /// Single shared timer for the app pipeline (optional for tests / headless).
    public var pipelineTimer: PipelineTimer?
    /// Called on the vision work queue after each successfully built `FramePayload` (for perf rollups).
    public var onFrameEmittedForPerf: (() -> Void)?
    /// Stale track ids pruned from the object tracker (see `ObjectTracker`).
    public var onStaleObjectPrune: ((Int) -> Void)?
    #if os(iOS)
    private var lastIntrinsics: CameraIntrinsics?
    #endif

    public init(detector: CoreMLDetector) {
        self.detector = detector
        self.config = detector.config
        let tr = ObjectTracker(
            highPriorityDistanceM: detector.config.highPriorityDistanceM
        )
        self.tracker = tr
        self.workQueue = DispatchQueue(
            label: "com.dualsight.vision",
            qos: .userInitiated
        )
        tr.onStalePrune = { [weak self] count in
            self?.onStaleObjectPrune?(count)
        }
    }

    deinit {
        workQueue.sync { }
    }

    /// Process one camera frame. `completion` is called on the **main** queue **only** when a `FramePayload` is emitted.
    /// Dropped frames (in-flight, rate limit) and handler errors do **not** call `completion` — avoids main-queue storms.
    public func process(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        intrinsics: CameraIntrinsics? = nil,
        arFrame: Any? = nil,
        completion: @escaping (FramePayload?) -> Void
    ) {
        workQueue.async { [weak self] in
            self?.processOnWorkQueue(
                pixelBuffer: pixelBuffer,
                orientation: orientation,
                intrinsics: intrinsics,
                arFrame: arFrame,
                completion: completion
            )
        }
    }

    private var consecutiveLidarFallbacks: [String: Int] = [:]
    private var wallAheadHitStreak: Int = 0
    private var wallAheadClearStreak: Int = 0
    private var wallAheadActive: Bool = false

    private func processOnWorkQueue(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        intrinsics: CameraIntrinsics?,
        arFrame: Any?,
        completion: @escaping (FramePayload?) -> Void
    ) {
        let captured = pixelBuffer
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        #if os(iOS)
        if let i = intrinsics { lastIntrinsics = i }
        guard let merged = intrinsics ?? lastIntrinsics else {
            return
        }
        lastIntrinsics = merged
        #else
        let merged = intrinsics
            ?? CameraIntrinsics.evalOnlyFromFrameDimensions(width: w, height: h, horizontalFOVDeg: 63)
        #endif

        stateLock.lock()
        if inFlight {
            stateLock.unlock()
            return
        }
        let now = CACurrentMediaTime()
        if now - lastEmitTime < config.minEmitInterval * 0.9 {
            stateLock.unlock()
            return
        }
        inFlight = true
        stateLock.unlock()

        let t0 = CACurrentMediaTime()

        let request = detector.makeRequest { [weak self] request, err in
            guard let self else { return }
            self.stateLock.lock()
            defer { self.inFlight = false; self.stateLock.unlock() }
            let raw = self.detector.buildObservations(
                from: request,
                error: err,
                imageWidth: w,
                imageHeight: h,
                intrinsics: merged
            )
            self.frameId += 1
            let fid = self.frameId
            let t1 = CACurrentMediaTime()
            let mapped = self.tracker.update(detections: raw, now: t1, frameIndex: fid)
            self.lastEmitTime = t1
            let visionMs = max(0, min(1_000_000, Int((t1 - t0) * 1000)))

            var dtos: [DetectedObjectDTO] = []
            let capability = detectDepthCapability()
            for o in mapped {
                var distanceM = o.distanceM
                var distanceConf: DistanceConfidence? = nil

                #if canImport(ARKit)
                if capability == .lidar, let frame = arFrame as? ARFrame {
                    // convert center-based bbox to top-left normalized rect
                    let minX = o.xCenterNorm - 0.5 * o.widthNorm
                    let minY = o.yCenterNorm - 0.5 * o.heightNorm
                    let bboxRect = CGRect(x: minX, y: minY, width: o.widthNorm, height: o.heightNorm)
                    let sample = sampleDepth(from: frame, bbox: bboxRect)
                    if sample.isValid {
                        distanceM = Double(sample.distanceM)
                        distanceConf = sample.distanceConfidence
                        // reset consecutive fallback counter
                        consecutiveLidarFallbacks[o.objectId] = 0
                    } else {
                        // LiDAR invalid — fall back to monocular but force low confidence and log
                        distanceConf = .low
                        consecutiveLidarFallbacks[o.objectId, default: 0] += 1
                        TelemetryRecorder.shared.record("lidar_fallback", objectID: o.objectId, className: o.className)
                        if consecutiveLidarFallbacks[o.objectId]! >= 5 {
                            TelemetryRecorder.shared.record("lidar_persistent_failure", objectID: o.objectId, className: o.className)
                        }
                    }
                }
                #endif

                dtos.append(
                    DetectedObjectDTO(
                        objectId: o.objectId,
                        objectClass: o.className,
                        confidence: (o.confidence * 100).rounded() / 100,
                        bbox: BBoxNorm(
                            xCenterNorm: o.xCenterNorm,
                            yCenterNorm: o.yCenterNorm,
                            widthNorm: o.widthNorm,
                            heightNorm: o.heightNorm
                        ),
                        distanceM: distanceM,
                        distanceConfidence: distanceConf,
                        panValue: o.panValue,
                        velocityMps: (o.velocityMps * 100).rounded() / 100,
                        priority: o.priority
                    )
                )
            }
            #if canImport(ARKit)
            if capability == .lidar, let frame = arFrame as? ARFrame {
                let wallProbe = self.sampleForwardWallDistance(from: frame)
                if wallProbe.isWall {
                    self.wallAheadHitStreak += 1
                    self.wallAheadClearStreak = 0
                    if self.wallAheadHitStreak >= 2 { self.wallAheadActive = true }
                } else {
                    self.wallAheadClearStreak += 1
                    self.wallAheadHitStreak = 0
                    if self.wallAheadClearStreak >= 2 { self.wallAheadActive = false }
                }

                if self.wallAheadActive {
                    let dist = wallProbe.distanceM ?? 1.5
                    dtos.append(
                        DetectedObjectDTO(
                            objectId: "wall_ahead",
                            objectClass: "wall",
                            confidence: 0.92,
                            bbox: BBoxNorm(
                                xCenterNorm: 0.5,
                                yCenterNorm: 0.5,
                                widthNorm: 0.9,
                                heightNorm: 0.9
                            ),
                            distanceM: dist,
                            distanceConfidence: .high,
                            panValue: 0,
                            velocityMps: 0,
                            priority: dist < self.config.highPriorityDistanceM ? "HIGH" : "NORMAL"
                        )
                    )
                }
            } else {
                self.wallAheadHitStreak = 0
                self.wallAheadClearStreak = 0
                self.wallAheadActive = false
            }
            #endif
            let cam: CameraHealthDTO? = {
                guard self.config.enableLensCheck else { return nil }
                let lap = LensQualityAnalyzer.laplacianVariance(
                    pixelBuffer: captured,
                    maxSide: self.config.lensCheckMaxSide
                )
                return self.lensState.update(lapVar: lap, config: self.config)
            }()
            let payload = FramePayload(
                frameId: fid,
                timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                visionDurationMs: visionMs,
                objects: dtos,
                camera: cam
            )
            DispatchQueue.main.async { completion(payload) }
        }

        // `VNCoreMLRequest.preferBackgroundProcessing` is set in `CoreMLDetector.makeRequest`.
        // (Do not use `VNImageOption` for this — the symbol is not available on all iOS SDKs.)
        do {
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )
            try handler.perform([request])
        } catch {
            stateLock.lock()
            inFlight = false
            stateLock.unlock()
            #if DEBUG
            print("VisionBridgeKit perform: \(error)")
            #endif
        }
    }

    public func resetTracker() {
        workQueue.async { [self] in
            self.stateLock.lock()
            self.tracker = ObjectTracker(
                highPriorityDistanceM: self.config.highPriorityDistanceM
            )
            self.stateLock.unlock()
            self.lensState.reset()
            self.wallAheadHitStreak = 0
            self.wallAheadClearStreak = 0
            self.wallAheadActive = false
        }
    }

    #if canImport(ARKit)
    /// Lightweight forward obstacle probe from LiDAR depth.
    /// Treat as "wall ahead" when enough near-depth samples are present in the center viewport.
    private func sampleForwardWallDistance(from frame: ARFrame) -> (isWall: Bool, distanceM: Double?) {
        guard let depthData = frame.smoothedSceneDepth else {
            return (false, nil)
        }
        let depthMap = depthData.depthMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let w = CVPixelBufferGetWidth(depthMap)
        let h = CVPixelBufferGetHeight(depthMap)
        guard let ptr = CVPixelBufferGetBaseAddress(depthMap) else {
            return (false, nil)
        }
        let depthFloats = ptr.bindMemory(to: Float32.self, capacity: w * h)

        let x0 = Int(Double(w) * 0.25)
        let x1 = Int(Double(w) * 0.75)
        let y0 = Int(Double(h) * 0.20)
        let y1 = Int(Double(h) * 0.80)
        if x1 <= x0 || y1 <= y0 {
            return (false, nil)
        }

        let stepX = max(1, (x1 - x0) / 24)
        let stepY = max(1, (y1 - y0) / 24)

        var validCount = 0
        var nearCount = 0
        var nearDepths: [Float] = []
        nearDepths.reserveCapacity(64)

        for y in stride(from: y0, to: y1, by: stepY) {
            for x in stride(from: x0, to: x1, by: stepX) {
                let d = depthFloats[y * w + x]
                guard d.isFinite, d > 0.15, d <= 4.0 else { continue }
                validCount += 1
                if d <= 2.0 {
                    nearCount += 1
                    nearDepths.append(d)
                }
            }
        }

        guard validCount >= 40 else { return (false, nil) }
        let nearRatio = Double(nearCount) / Double(validCount)
        guard nearRatio >= 0.60, !nearDepths.isEmpty else { return (false, nil) }

        nearDepths.sort()
        let median = Double(nearDepths[nearDepths.count / 2])
        return (true, median)
    }
    #endif
}
