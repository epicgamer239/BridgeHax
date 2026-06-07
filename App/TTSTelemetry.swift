import Foundation

enum TTSDropReason: String, Codable {
    case dedupe
    case muted
    case lowPriorityInCritical
    case queueFull
    case ttlExpired
    case sceneFlush
    case disabled
    case noDetections
    case unknown
    case distanceClamp
}

struct TTSEvent: Codable {
    let timestamp: Date
    let utterance: String?
    let priority: String?
    let queueDepthAtEnqueue: Int?
    let dropReason: TTSDropReason?
    let timeToSpeakMs: Int?
    let voiceIdentifier: String?
}

final class TTSTelemetryStore {
    static let shared = TTSTelemetryStore()
    private init() {}

    private let lock = NSLock()
    private var enabled = false
    private var ring: [TTSEvent] = []
    private let cap = 500

    func setEnabled(_ on: Bool) {
        lock.withLock {
            enabled = on
            if !on { ring.removeAll() }
        }
    }

    func record(_ e: TTSEvent) {
        lock.withLock {
            guard enabled else { return }
            ring.append(e)
            if ring.count > cap {
                ring.removeFirst(ring.count - cap)
            }
        }
    }

    func snapshot() -> [TTSEvent] {
        lock.withLock { ring }
    }

    func exportJSONFile() throws -> URL {
        let events = snapshot()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(events)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tts-telemetry-\(Int(Date().timeIntervalSince1970)).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
