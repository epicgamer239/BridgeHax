import CoreFoundation
import Foundation
import os

/// Wall-clock pipeline stages. Hot-path `begin`/`end` are allocation-free; internal locking keeps cross-thread use safe.
public final class PipelineTimer: @unchecked Sendable {
    public enum Stage: Int, CaseIterable, Sendable {
        case frameIngest
        case inference
        case postprocess
        case speechDecision
        case utteranceStart
    }

    private var starts: [CFAbsoluteTime] = [CFAbsoluteTime](repeating: 0, count: Stage.allCases.count)
    private var durations: [Double] = [Double](repeating: 0, count: Stage.allCases.count)
    private var unfair = os_unfair_lock()

    public init() {}

    @inline(__always)
    public func begin(_ stage: Stage) {
        let t = CFAbsoluteTimeGetCurrent()
        os_unfair_lock_lock(&unfair)
        starts[stage.rawValue] = t
        os_unfair_lock_unlock(&unfair)
    }

    @inline(__always)
    public func end(_ stage: Stage) {
        let t = CFAbsoluteTimeGetCurrent()
        let idx = stage.rawValue
        os_unfair_lock_lock(&unfair)
        let elapsed = t - starts[idx]
        durations[idx] = elapsed
        os_unfair_lock_unlock(&unfair)
    }

    public var totalLatencyMs: Double {
        os_unfair_lock_lock(&unfair)
        let sum = durations.reduce(0, +) * 1000.0
        os_unfair_lock_unlock(&unfair)
        return sum
    }

    /// For telemetry: call from a non-hot context only.
    public func report() -> [String: Double] {
        var out: [String: Double] = [:]
        out.reserveCapacity(Stage.allCases.count)
        os_unfair_lock_lock(&unfair)
        for s in Stage.allCases {
            out[s.debugName] = durations[s.rawValue] * 1000.0
        }
        os_unfair_lock_unlock(&unfair)
        return out
    }
}

private extension PipelineTimer.Stage {
    var debugName: String {
        switch self {
        case .frameIngest: "frame_ingest_ms"
        case .inference: "inference_ms"
        case .postprocess: "postprocess_ms"
        case .speechDecision: "speech_decision_ms"
        case .utteranceStart: "utterance_start_ms"
        }
    }
}
