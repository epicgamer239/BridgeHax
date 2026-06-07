import AVFoundation
import VisionBridgeKit
import Combine
import Foundation

/// TTS-only hearing runtime: no spatial audio graph.
/// High-priority lines are scheduled on a LIFO stack, normal lines on a FIFO queue.
final class HearingEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var objectCount: Int = 0
    @Published private(set) var alertActive: Bool = false
    @Published private(set) var lastBridgeLatencyMs: Int?
    @Published private(set) var isUsingOnDevicePayload: Bool = false

    private struct SpeechItem: Sendable {
        enum Priority: Sendable { case high, normal }
        let id: String
        let text: String
        let priority: Priority
        let enqueuedAt: Date
    }

    private struct SpokenSnapshot: Sendable {
        let distanceM: Double
        let pan: Double
        let at: Date
    }

    private struct VisibilityStreak: Sendable {
        var firstSeenAt: Date
        var lastSeenAt: Date
        var lastSeenFrameId: Int
        var consecutiveFrames: Int
    }

    private let speechSynth = AVSpeechSynthesizer()
    private let phraseBuilder = PhraseBuilder()
    private var distanceAssessor = DistanceConfidenceAssessor(alpha: 0.3)
    private var dedupePolicy = DedupePolicy(idCooldown: 7.0, classCooldown: 4.0)
    private let workQueue = DispatchQueue(label: "com.dualsight.hearing.work", qos: .userInitiated)
    private var speechTimer: DispatchSourceTimer?

    // Scheduling buffers: high is stack (LIFO), normal is queue (FIFO).
    private var highPriorityStack: [SpeechItem] = []
    private var normalPriorityQueue: [SpeechItem] = []
    private var queuedIds: Set<String> = []

    private var lastSpokenByObjectId: [String: Date] = [:]
    private var lastSpokenByClass: [String: Date] = [:]
    private var lastSpokenBySpatialKey: [String: Date] = [:]
    private var lastSpokenSnapshotByObjectId: [String: SpokenSnapshot] = [:]
    private var lastSeenByObjectId: [String: Date] = [:]
    private var visibilityStreakByObjectId: [String: VisibilityStreak] = [:]
    private var lastSpokenPanByClass: [String: Double] = [:]
    private var lastSpeechAt: Date?
    private var lastPeopleGroupSpokenAt: Date?
    private var lastSpokenObjectCount: Int = 0
    /// Consecutive processed frames with no high-confidence pool (debounces detection flicker).
    private var consecutiveEmptyPoolFrames: Int = 0
    private var lastForcedSpeakAt: Date?
    private var mutedUntil: Date?
    /// Mirrored from `AVSpeechSynthesizerDelegate` on the work queue — never use `main.sync` to read `isSpeaking`.
    private var synthesizerIsSpeaking: Bool = false
    private var noDetectionsAnnouncedAt: Date?
    private var systemMessageKeys: Set<String> = []
    private var recentCriticalUtterances: [Date] = []
    private var featureToggleDebounce: DispatchWorkItem?

    private let cooldownSameTrackSeconds: TimeInterval = 10.0
    private let cooldownSameSpatialCellSeconds: TimeInterval = 4.0
    private static let cooldownSameClassSeconds: TimeInterval = 4.0
    /// Large static furniture can split into many tracks; longer cooldown limits repeat labels.
    private static let cooldownSameFurnitureClassSeconds: TimeInterval = 4.0
    /// Desk / screen objects share the spoken label "Computer" — one cue is enough while the scene stays stable.
    private static let cooldownSameComputerPhraseSeconds: TimeInterval = 3.0
    private let minIntervalAnySpeechSeconds: TimeInterval = 0.85
    private let peopleGroupCooldownSeconds: TimeInterval = 7.0
    private let maxAnnouncementsPerFrame: Int = 1
    private let maxQueuedItemsPerTier = 6
    private let itemTTLSeconds: TimeInterval = 1.1
    private let forcedSpeakFallbackSeconds: TimeInterval = 2.2
    private let noDetectionsAnnounceSeconds: TimeInterval = 12.0
    private static let maxPanAnySpeech: Double = 0.62
    private static let maxPanDefault: Double = 0.24
    private static let maxPanImportant: Double = 0.42
    private static let maxPanLowValue: Double = 0.10

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 0.066
    private var cancellable: AnyCancellable?
    private weak var vision: VisionBridgeSession?
    private var isRunning: Bool = false

    private let speechGateLock = NSLock()
    private var allowsFrameSpeech: Bool = false
    private static let minConfidenceForSpeech: Double = 0.62
    /// Debounce transient detections before first spoken cue.
    private let minStableFramesForSpeech = 3
    private static let bridgeURLKey = "dualsight.visionBridgeBaseURLString"

    static var defaultBridgeBaseURL: URL { URL(string: "http://127.0.0.1:8765")! }

    private static func loadBridgeBaseFromDefaults() -> URL {
        if let s = UserDefaults.standard.string(forKey: bridgeURLKey), !s.isEmpty, let u = URL(string: s) {
            return u
        }
        return defaultBridgeBaseURL
    }

    override init() {
        super.init()
        speechSynth.delegate = self
        configureAudioSession()
    }

    deinit { stop() }

    @MainActor func reconfigure(vision: VisionBridgeSession?) {
        self.vision = vision
        isUsingOnDevicePayload = vision != nil
        rewire()
    }

    @MainActor func reconfigure(bridgeBase: URL) {
        UserDefaults.standard.set(bridgeBase.absoluteString, forKey: Self.bridgeURLKey)
        if vision == nil { rewire() }
    }

    /// Coalesces Settings UI churn (picker sends many `onChange` events) into one flush and avoids queue hammering.
    func applyFeatureTogglesFromUserDefaults() {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.featureToggleDebounce?.cancel()
            let w = DispatchWorkItem { [weak self] in
                self?.hardFlushSpeech(reason: "tts feature toggle changed")
            }
            self.featureToggleDebounce = w
            self.workQueue.asyncAfter(deadline: .now() + 0.25, execute: w)
        }
    }

    func setVisionSpeechEnabled(_ enabled: Bool) {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.speechGateLock.lock()
            self.allowsFrameSpeech = enabled
            self.speechGateLock.unlock()
            if !enabled { self.hardFlushSpeech(reason: "speech disabled") }
        }
    }

    func muteFor(seconds: TimeInterval) {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.mutedUntil = Date().addingTimeInterval(seconds)
            self.hardFlushSpeech(reason: "manual mute")
            self.telemetryDrop(.muted)
        }
    }

    func unmuteNow() {
        workQueue.async { [weak self] in
            self?.mutedUntil = nil
        }
    }

    var isMuted: Bool {
        if let until = mutedUntil { return Date() < until }
        return false
    }

    func announceSystemMessageOnce(key: String, message: String) {
        workQueue.async { [weak self] in
            guard let self else { return }
            if self.systemMessageKeys.contains(key) { return }
            self.systemMessageKeys.insert(key)
            let item = SpeechItem(
                id: "system-\(key)",
                text: message,
                priority: .high,
                enqueuedAt: Date()
            )
            self.enqueue(item)
        }
    }

    /// Speaks a line immediately, bypassing cooldowns and system message history.
    /// Use this for UI feedback (e.g. "Scanning started").
    func speakImmediate(_ text: String) {
        workQueue.async { [weak self] in
            guard let self else { return }
            let item = SpeechItem(
                id: "immediate-\(UUID().uuidString)",
                text: text,
                priority: .high,
                enqueuedAt: Date()
            )
            self.enqueue(item)
        }
    }

    @MainActor func start(vision: VisionBridgeSession?) {
        self.vision = vision
        isUsingOnDevicePayload = vision != nil
        isRunning = true
        startSpeechScheduler()
        rewire()
    }

    func stop() {
        isRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
        cancellable = nil
        speechTimer?.cancel()
        speechTimer = nil
        DispatchQueue.main.async { [weak self] in
            self?.speechSynth.stopSpeaking(at: .immediate)
        }
    }

    private func configureAudioSession() {
        DispatchQueue.main.async {
            let s = AVAudioSession.sharedInstance()
            do {
                // Resolved -50 error: .allowBluetoothHFP is only for .playAndRecord.
                // Added .duckOthers to ensure guidance is heard clearly.
                try s.setCategory(
                    .playback,
                    mode: .spokenAudio,
                    options: [.allowBluetoothA2DP, .mixWithOthers, .duckOthers]
                )
                try s.setActive(true, options: [])
            } catch {
                #if DEBUG
                print("Hearing: AVAudioSession config failed:", error)
                #endif
            }
            let v = self.preferredVoice()
            TTSTelemetryStore.shared.record(
                TTSEvent(
                    timestamp: Date(),
                    utterance: nil,
                    priority: nil,
                    queueDepthAtEnqueue: nil,
                    dropReason: nil,
                    timeToSpeakMs: nil,
                    voiceIdentifier: v?.identifier ?? "system-default"
                )
            )
        }
    }

    private func startSpeechScheduler() {
        if speechTimer != nil { return }
        let t = DispatchSource.makeTimerSource(queue: workQueue)
        t.schedule(deadline: .now(), repeating: .milliseconds(90))
        t.setEventHandler { [weak self] in
            self?.drainSpeechBacklogIfPossible()
        }
        speechTimer = t
        t.resume()
    }

    @MainActor private func rewire() {
        pollTimer?.invalidate()
        pollTimer = nil
        cancellable = nil

        if let v = vision {
            isUsingOnDevicePayload = true
            cancellable = v.$lastPayload
                .compactMap { $0 }
                .receive(on: workQueue)
                .sink { [weak self] p in
                    self?.handleFrame(p)
                }
        } else {
            isUsingOnDevicePayload = false
            guard isRunning else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pollTimer = Timer.scheduledTimer(withTimeInterval: self.pollInterval, repeats: true) { [weak self] _ in
                    self?.fetchFrameFromBridge()
                }
                if let t = self.pollTimer { RunLoop.main.add(t, forMode: .common) }
            }
        }
    }

    private func fetchFrameFromBridge() {
        let base = Self.loadBridgeBaseFromDefaults()
        let u = base.appendingPathComponent("frame", isDirectory: false)
        let t0 = Date()
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.lastBridgeLatencyMs != ms { self.lastBridgeLatencyMs = ms }
            }
            guard let self, let data else { return }
            do {
                let frame = try JSONDecoder().decode(FramePayload.self, from: data)
                self.workQueue.async { self.handleFrame(frame) }
            } catch {
                #if DEBUG
                print("Hearing: bridge decode failed:", error)
                #endif
            }
        }.resume()
    }

    private func handleFrame(_ frame: FramePayload) {
        speechGateLock.lock()
        let allow = allowsFrameSpeech
        speechGateLock.unlock()
        guard allow else { return }
        if let until = mutedUntil, Date() < until { return }

        pruneState(now: Date())
        
        // Update visibility tracking
        let currentObjectIds = Set(frame.objects.map { $0.objectId })
        pruneStaleObjects(currentIds: currentObjectIds)

        for obj in frame.objects {
            lastSeenByObjectId[obj.objectId] = Date()
        }

        let includeDistance = VisionBridgeFeatureFlags.hearingTTS
        let announceEach = VisionBridgeFeatureFlags.hearingTones

        let pool = frame.objects
            .filter { obj in
                let tier = Self.safetyTier(for: obj.objectClass)
                let threshold: Double
                switch tier {
                case .critical: threshold = 0.45
                case .obstacle: threshold = 0.52
                case .context:  threshold = 0.60
                case .lowValue: threshold = 0.72
                }
                return obj.confidence >= threshold
            }
            .filter { !VisionBridgeFeatureFlags.suppressedClasses.contains($0.objectClass.lowercased()) }
            .filter { Self.passesPanGate($0) }
            .sorted { Self.interestScore($0) > Self.interestScore($1) }

        if pool.count == 0 {
            if let t = noDetectionsAnnouncedAt, Date().timeIntervalSince(t) < noDetectionsAnnounceSeconds {
                // do nothing
            } else {
                enqueue(
                    SpeechItem(
                        id: "no-detections-\(Int(Date().timeIntervalSince1970))",
                        text: "No obstacles detected",
                        priority: .normal,
                        enqueuedAt: Date()
                    )
                )
                noDetectionsAnnouncedAt = Date()
            }
        } else {
            noDetectionsAnnouncedAt = nil
        }

        updateVisibilityStreaks(for: pool, frameId: frame.frameId, now: Date())

        if pool.isEmpty {
            consecutiveEmptyPoolFrames = min(consecutiveEmptyPoolFrames + 1, 1_000)
        } else {
            consecutiveEmptyPoolFrames = 0
        }
        if shouldFlushForSceneChange(newCount: pool.count) {
            hardFlushSpeech(reason: "scene changed")
        }
        if lastSpokenObjectCount > 0, pool.count * 2 < lastSpokenObjectCount {
            // Requirement 1.3: >50% drop -> flush normal queue immediately.
            flushNormalQueue(reason: "scene drop >50%")
        }

        // --- NEW: Spatial Haptics (Physical UI) ---
        // We pulse haptics for every frame that contains high-priority or very close hazards,
        // ensuring a "physical connection" even when speech is suppressed by dedupe gates.
        if !pool.isEmpty {
            let topObj = pool[0]
            let isHigh = topObj.priority.lowercased() == "high"
            let isVeryClose = topObj.distanceM < 2.5
            
            if isHigh || isVeryClose {
                DispatchQueue.main.async {
                    let manager = HapticManager.shared
                    if topObj.distanceM < 1.5 {
                        manager.triggerCriticalThreat()
                    } else if isHigh {
                        manager.triggerWarning()
                    } else {
                        manager.triggerDiscovery()
                    }
                }
            }
        }

        var emitted = 0
        for obj in pool {
            if emitted >= maxAnnouncementsPerFrame { break }
            if let item = buildSpeechItem(for: obj, includeDistance: includeDistance, announceEach: announceEach) {
                enqueue(item)
                markSpoken(obj: obj, now: item.enqueuedAt)
                emitted += 1
            }
        }
        // Failsafe: if detections are present but strict dedupe/noise gates suppressed all speech,
        // announce the top object periodically so users are never left with silent detections.
        if announceEach, emitted == 0, let top = pool.first {
            let now = Date()
            let speechCat = Self.speechDedupeCategory(forClassKey: top.objectClass.lowercased())
            let phraseGap = Self.cooldownSecondsForSpeechCategory(speechCat, rawClassKey: top.objectClass.lowercased())
            let recentlySpokeThisPhrase =
                (lastSpokenByClass[speechCat]).map { now.timeIntervalSince($0) < phraseGap } ?? false
            if recentlySpokeThisPhrase {
                // Failsafe must not bypass phrase cooldowns (otherwise "Computer" every ~2s forever).
            } else if !passesPersistenceGate(obj: top, now: now) {
                // Keep failsafe aligned with persistence debounce for first-time detections.
            } else if lastForcedSpeakAt == nil || now.timeIntervalSince(lastForcedSpeakAt!) >= forcedSpeakFallbackSeconds {
                let phrase = phraseForObject(top, includeDistance: includeDistance)
                let forced = SpeechItem(
                    id: "forced|\(top.objectId)|\(Int(now.timeIntervalSince1970))",
                    text: phrase,
                    priority: .normal,
                    enqueuedAt: now
                )
                enqueue(forced)
                lastForcedSpeakAt = now
                markSpoken(obj: top, now: now)
            }
        }

        let alert = frame.objects.contains { $0.distanceM < 3.0 && abs($0.velocityMps) > 1.5 }
        lastSpokenObjectCount = pool.count
        let newCount = frame.objects.count
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.objectCount != newCount { self.objectCount = newCount }
            if self.alertActive != alert { self.alertActive = alert }
        }
    }

    private func buildSpeechItem(
        for obj: DetectedObjectDTO,
        includeDistance: Bool,
        announceEach: Bool
    ) -> SpeechItem? {
        let now = Date()
        if !passesPersistenceGate(obj: obj, now: now) { return nil }
        if !passesDedupeGates(obj: obj, now: now) { return nil }

        let isHigh = obj.priority.uppercased() == "HIGH"
        if VisionBridgeFeatureFlags.ttsCriticalOnly {
            let classKey = obj.objectClass.lowercased()
            if !(DetectionConfig.highPriorityClasses.contains(classKey) && obj.distanceM < 3.0) {
                telemetryDrop(.lowPriorityInCritical)
                return nil
            }
            let now = Date()
            recentCriticalUtterances = recentCriticalUtterances.filter { now.timeIntervalSince($0) < 5.0 }
            if recentCriticalUtterances.count >= 2 {
                telemetryDrop(.dedupe, utterance: "critical-window-limit")
                return nil
            }
            recentCriticalUtterances.append(now)
        }
        if !announceEach && !isHigh { return nil }
        let lowNoise = VisionBridgeFeatureFlags.ttsVerbosity == "low"
        var phrase = phraseForObject(obj, includeDistance: includeDistance)
        if lowNoise {
            // In low-noise mode, keep utterances short and avoid filler words.
            phrase = phrase.replacingOccurrences(of: "straight ahead", with: "ahead")
        }
        let itemId = "\(obj.objectId)|\(Int(now.timeIntervalSince1970 * 10))"
        return SpeechItem(
            id: itemId,
            text: phrase,
            priority: isHigh ? .high : .normal,
            enqueuedAt: now
        )
    }

    private func enqueue(_ item: SpeechItem) {
        if queuedIds.contains(item.id) { return }
        queuedIds.insert(item.id)
        let depthBefore = highPriorityStack.count + normalPriorityQueue.count
        TTSTelemetryStore.shared.record(
            TTSEvent(
                timestamp: Date(),
                utterance: item.text,
                priority: item.priority == .high ? "high" : "normal",
                queueDepthAtEnqueue: depthBefore,
                dropReason: nil,
                timeToSpeakMs: nil,
                voiceIdentifier: nil
            )
        )
        switch item.priority {
        case .high:
            highPriorityStack.append(item) // stack: LIFO
            if highPriorityStack.count > maxQueuedItemsPerTier {
                let dropCount = highPriorityStack.count - maxQueuedItemsPerTier
                let removed = Array(highPriorityStack.prefix(dropCount))
                highPriorityStack.removeFirst(dropCount)
                for r in removed {
                    queuedIds.remove(r.id)
                    telemetryDrop(.queueFull, utterance: r.text)
                }
            }
        case .normal:
            normalPriorityQueue.append(item) // queue: FIFO
            if normalPriorityQueue.count > maxQueuedItemsPerTier {
                let dropCount = normalPriorityQueue.count - maxQueuedItemsPerTier
                let removed = Array(normalPriorityQueue.prefix(dropCount))
                normalPriorityQueue.removeFirst(dropCount)
                for r in removed {
                    queuedIds.remove(r.id)
                    telemetryDrop(.queueFull, utterance: r.text)
                }
            }
        }
    }

    private func drainSpeechBacklogIfPossible() {
        pruneExpiredQueuedItems()
        let now = Date()
        if let t = lastSpeechAt, now.timeIntervalSince(t) < minIntervalAnySpeechSeconds { return }
        if synthesizerIsSpeaking { return }

        let next: SpeechItem?
        if let hi = highPriorityStack.popLast() {
            next = hi
        } else if !normalPriorityQueue.isEmpty {
            next = normalPriorityQueue.removeFirst()
        } else {
            next = nil
        }
        guard let item = next else { return }
        queuedIds.remove(item.id)
        lastSpeechAt = now
        let latencyMs = Int(now.timeIntervalSince(item.enqueuedAt) * 1000)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let u = AVSpeechUtterance(string: item.text)
            u.voice = self.preferredVoice()
            switch VisionBridgeFeatureFlags.ttsVoiceStyle {
            case "compact":
                u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
                u.pitchMultiplier = 1.02
            case "clear":
                u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.90
                u.pitchMultiplier = 1.0
            default: // calm — slightly slower, lower pitch for a soothing read
                u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.80
                u.pitchMultiplier = 0.92
            }
            u.preUtteranceDelay = 0.02
            self.speechSynth.speak(u)
        }
        TTSTelemetryStore.shared.record(
            TTSEvent(
                timestamp: now,
                utterance: item.text,
                priority: item.priority == .high ? "high" : "normal",
                queueDepthAtEnqueue: nil,
                dropReason: nil,
                timeToSpeakMs: latencyMs,
                voiceIdentifier: preferredVoice()?.identifier
            )
        )
    }

    private func pruneStaleObjects(currentIds: Set<String>) {
        let filterBlock: (SpeechItem) -> Bool = { item in
            // Extract objectId from "objectId|timestamp" format
            let parts = item.id.split(separator: "|")
            guard parts.count >= 1 else { return true }
            let objId = String(parts[0])
            
            // If it's a system message or forced announcement, don't prune based on viewport
            if item.id.contains("no-detections") || item.id.contains("forced") || item.id.contains("system") {
                return true
            }
            
            let stillInView = currentIds.contains(objId)
            if !stillInView {
                self.queuedIds.remove(item.id)
                self.telemetryDrop(.sceneFlush, utterance: "viewport-exit:\(item.text)")
            }
            return stillInView
        }
        
        highPriorityStack = highPriorityStack.filter(filterBlock)
        normalPriorityQueue = normalPriorityQueue.filter(filterBlock)
    }

    private func pruneExpiredQueuedItems() {
        let now = Date()
        highPriorityStack = highPriorityStack.filter {
            let ok = now.timeIntervalSince($0.enqueuedAt) <= itemTTLSeconds
            if !ok {
                queuedIds.remove($0.id)
                telemetryDrop(.ttlExpired, utterance: $0.text)
            }
            return ok
        }
        normalPriorityQueue = normalPriorityQueue.filter {
            let ok = now.timeIntervalSince($0.enqueuedAt) <= itemTTLSeconds
            if !ok {
                queuedIds.remove($0.id)
                telemetryDrop(.ttlExpired, utterance: $0.text)
            }
            return ok
        }
    }

    private func hardFlushSpeech(reason: String) {
        synthesizerIsSpeaking = false
        highPriorityStack.removeAll()
        normalPriorityQueue.removeAll()
        queuedIds.removeAll()
        lastSpokenByObjectId.removeAll()
        lastSpokenBySpatialKey.removeAll()
        lastSpokenByClass.removeAll()
        lastSpokenSnapshotByObjectId.removeAll()
        visibilityStreakByObjectId.removeAll()
        dedupePolicy.reset()
        lastSpeechAt = nil
        lastPeopleGroupSpokenAt = nil
        #if DEBUG
        print("Hearing: flush:", reason)
        #endif
        telemetryDrop(.sceneFlush)
        DispatchQueue.main.async { [weak self] in
            self?.speechSynth.stopSpeaking(at: .immediate)
        }
    }

    private func flushNormalQueue(reason: String) {
        if !normalPriorityQueue.isEmpty {
            for i in normalPriorityQueue {
                telemetryDrop(.sceneFlush, utterance: i.text)
                queuedIds.remove(i.id)
            }
            normalPriorityQueue.removeAll()
            #if DEBUG
            print("Hearing: normal queue flush:", reason)
            #endif
        }
    }

    private func shouldFlushForSceneChange(newCount: Int) -> Bool {
        let prev = lastSpokenObjectCount
        // Require two empty frames so single-frame detection gaps do not clear the whole queue and spam logs.
        if newCount == 0, prev > 0, consecutiveEmptyPoolFrames >= 2 { return true }
        if prev >= 10, newCount <= 1 { return true }
        if prev - newCount >= 6, newCount * 2 < prev { return true }
        return false
    }

    private func pruneState(now: Date) {
        let cap: TimeInterval = 45
        let classCap: TimeInterval = 10
        let visibilityCap: TimeInterval = 3
        lastSpokenByObjectId = lastSpokenByObjectId.filter { now.timeIntervalSince($0.value) < cap }
        lastSpokenBySpatialKey = lastSpokenBySpatialKey.filter { now.timeIntervalSince($0.value) < cap }
        lastSpokenByClass = lastSpokenByClass.filter { now.timeIntervalSince($0.value) < classCap }
        lastSpokenSnapshotByObjectId = lastSpokenSnapshotByObjectId.filter { now.timeIntervalSince($0.value.at) < cap }
        lastSeenByObjectId = lastSeenByObjectId.filter { now.timeIntervalSince($0.value) < cap }
        visibilityStreakByObjectId = visibilityStreakByObjectId.filter { now.timeIntervalSince($0.value.lastSeenAt) < visibilityCap }
        lastSpokenPanByClass = lastSpokenPanByClass.filter {
            if let last = lastSpokenByClass[$0.key] {
                return now.timeIntervalSince(last) < classCap
            }
            return false
        }
    }

    private func updateVisibilityStreaks(for pool: [DetectedObjectDTO], frameId: Int, now: Date) {
        let currentIds = Set(pool.map(\.objectId))
        for obj in pool {
            if let prior = visibilityStreakByObjectId[obj.objectId] {
                let contiguous = frameId - prior.lastSeenFrameId <= 1
                let newFirstSeen = contiguous ? prior.firstSeenAt : now
                let newCount = contiguous ? prior.consecutiveFrames + 1 : 1
                visibilityStreakByObjectId[obj.objectId] = VisibilityStreak(
                    firstSeenAt: newFirstSeen,
                    lastSeenAt: now,
                    lastSeenFrameId: frameId,
                    consecutiveFrames: newCount
                )
            } else {
                visibilityStreakByObjectId[obj.objectId] = VisibilityStreak(
                    firstSeenAt: now,
                    lastSeenAt: now,
                    lastSeenFrameId: frameId,
                    consecutiveFrames: 1
                )
            }
        }
        // Drop streaks that are no longer in this confidence-filtered pool.
        visibilityStreakByObjectId = visibilityStreakByObjectId.filter { currentIds.contains($0.key) }
    }

    private func passesPersistenceGate(obj: DetectedObjectDTO, now: Date) -> Bool {
        guard let streak = visibilityStreakByObjectId[obj.objectId] else { return false }
        if streak.consecutiveFrames < minStableFramesForSpeech {
            telemetryDrop(.dedupe)
            return false
        }
        return true
    }

    private func passesDedupeGates(obj: DetectedObjectDTO, now: Date) -> Bool {
        if !dedupePolicy.shouldSpeak(objectID: obj.objectId, objectClass: obj.objectClass, distance: obj.distanceM) {
            telemetryDrop(.dedupe)
            return false
        }
        if let last = lastSpokenByObjectId[obj.objectId], now.timeIntervalSince(last) < cooldownSameTrackSeconds {
            telemetryDrop(.dedupe)
            return false
        }
        if let snap = lastSpokenSnapshotByObjectId[obj.objectId] {
            let dd = abs(snap.distanceM - obj.distanceM)
            let dp = abs(snap.pan - obj.panValue)
            let dt = now.timeIntervalSince(snap.at)
            
            // Look-away-and-back detection: if object was absent for > 0.4s, allow immediate re-speak
            let lastSeen = lastSeenByObjectId[obj.objectId] ?? .distantPast
            let absence = now.timeIntervalSince(lastSeen)
            
            // If object hasn't moved/changed enough, and hasn't been gone, do not repeat it too soon.
            let trackCooldown: TimeInterval = 3.0 // Reduced from 8.0 for faster rhythm
            if dt < trackCooldown && dd < 0.7 && dp < 0.18 && absence < 0.4 {
                telemetryDrop(.dedupe)
                return false
            }
        }
        let classKey = obj.objectClass.lowercased()
        let speechCat = Self.speechDedupeCategory(forClassKey: classKey)
        if classKey == "person" {
            if let last = lastPeopleGroupSpokenAt, now.timeIntervalSince(last) < peopleGroupCooldownSeconds {
                telemetryDrop(.dedupe)
                return false
            }
            lastPeopleGroupSpokenAt = now
        }
        let classGap = Self.cooldownSecondsForSpeechCategory(speechCat, rawClassKey: classKey)
        if let last = lastSpokenByClass[speechCat], now.timeIntervalSince(last) < classGap {
            // Spatial Class Bypass: If this same class was spoken recently, 
            // but the current object is at a significantly different pan, allow it.
            let lastPan = lastSpokenPanByClass[speechCat] ?? 0.0
            let panDelta = abs(obj.panValue - lastPan)
            if panDelta < 0.35 { // Only block if it's in a similar horizontal zone
                telemetryDrop(.dedupe)
                return false
            }
        }
        let sk = Self.spatialDedupeKey(obj: obj)
        if let last = lastSpokenBySpatialKey[sk], now.timeIntervalSince(last) < cooldownSameSpatialCellSeconds {
            telemetryDrop(.dedupe)
            return false
        }
        return true
    }

    private func markSpoken(obj: DetectedObjectDTO, now: Date) {
        dedupePolicy.recordSpoken(objectID: obj.objectId, objectClass: obj.objectClass)
        lastSpokenByObjectId[obj.objectId] = now
        let speechCat = Self.speechDedupeCategory(forClassKey: obj.objectClass.lowercased())
        lastSpokenByClass[speechCat] = now
        lastSpokenPanByClass[speechCat] = obj.panValue
        lastSpokenBySpatialKey[Self.spatialDedupeKey(obj: obj)] = now
        lastSpokenSnapshotByObjectId[obj.objectId] = SpokenSnapshot(
            distanceM: obj.distanceM,
            pan: obj.panValue,
            at: now
        )
    }

    private static func spatialDedupeKey(obj: DetectedObjectDTO) -> String {
        let c = speechDedupeCategory(forClassKey: obj.objectClass.lowercased())
        let x = Int((obj.bbox.xCenterNorm * 15.0).rounded())
        let y = Int((obj.bbox.yCenterNorm * 15.0).rounded())
        return "\(c)|\(x)|\(y)"
    }

    /// Groups raw classes that share the same `ObjectSpokenName` so we do not repeat "Computer" for keyboard vs monitor vs TV.
    private static func speechDedupeCategory(forClassKey classKey: String) -> String {
        ObjectSpokenName.phrase(classKey).lowercased()
    }

    private static func cooldownSecondsForSpeechCategory(_ category: String, rawClassKey: String) -> TimeInterval {
        if category == "computer" { return cooldownSameComputerPhraseSeconds }
        if longClassCooldownFurniture.contains(rawClassKey) { return cooldownSameFurnitureClassSeconds }
        return cooldownSameClassSeconds
    }

    private static func interestScore(_ o: DetectedObjectDTO) -> Double {
        let d = max(0.1, o.distanceM)
        let pri = o.priority.uppercased() == "HIGH" ? 1.8 : 1.0
        let w = classImportance(o.objectClass)
        let centerBias = max(0.45, 1.35 - abs(o.panValue))
        return w * pri * centerBias * (1.0 / d) * (0.55 + 0.45 * min(1.0, o.confidence))
    }

    private enum SafetyTier {
        case critical, obstacle, context, lowValue
    }

    private static func safetyTier(for raw: String) -> SafetyTier {
        let t = raw.lowercased()
        
        // Tier 1: Critical Hazards (Life & Limb)
        let criticalKeywords = [
            "person", "man", "woman", "boy", "girl",
            "car", "truck", "bus", "train", "ambulance", "vehicle", "aircraft", "airplane",
            "bicycle", "motorcycle",
            "dog", "animal", "bear", "bull", "lion", "tiger", "horse", "elephant",
            "traffic light", "traffic sign", "stop sign", "fire hydrant",
            "stairs", "staircase", "escalator"
        ]
        if criticalKeywords.contains(where: { t.contains($0) }) { return .critical }
        
        // Tier 2: Mobility Obstacles (Tripping & Path)
        let obstacleKeywords = [
            "chair", "table", "couch", "bench", "bed", "furniture", "desk", "stool",
            "door", "window", "gate", "fence", "wall",
            "waste container", "trash", "bin",
            "cart", "stroller", "wheelchair"
        ]
        if obstacleKeywords.contains(where: { t.contains($0) }) { return .obstacle }
        
        // Tier 4: Low-Value / Noise (Electronics & Small items)
        let lowValueKeywords = [
            "laptop", "television", "phone", "monitor", "keyboard", "mouse", "remote", "camera", "tablet",
            "cup", "bowl", "plate", "fork", "knife", "spoon", "glass", "bottle",
            "book", "magazine", "paper", "pen", "pencil",
            "toy", "ball", "doll", "game",
            "clothing", "shoe", "boot", "hat", "sock", "shirt", "pants"
        ]
        if lowValueKeywords.contains(where: { t.contains($0) }) { return .lowValue }
        
        // Tier 3: Everything else (Buildings, Plants, etc.)
        return .context
    }

    private static func classImportance(_ raw: String) -> Double {
        let tier = safetyTier(for: raw)
        switch tier {
        case .critical: return 3.5
        case .obstacle: return 2.2
        case .context:  return 1.0
        case .lowValue: return 0.15
        }
    }

    private static func passesPanGate(_ o: DetectedObjectDTO) -> Bool {
        let panAbs = abs(o.panValue)
        // Hard cap: never narrate extreme side detections.
        if panAbs > maxPanAnySpeech { return false }

        let t = o.objectClass.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isLowValue = t == "chair"
            || t == "couch"
            || t == "bench"
            || t == "kitchen & dining room table"
            || t == "plant"
            || t == "coffee cup"

        if isLowValue {
            return panAbs <= maxPanLowValue
        }

        let isImportantClass = t == "truck"
            || t == "bus"
            || t == "car"
            || t == "motorcycle"
            || t == "bicycle"
            || t == "person"
            || t == "stairs"
            || t == "waste container"

        let isHighPriority = o.priority.uppercased() == "HIGH"
        if isHighPriority || isImportantClass {
            return panAbs <= maxPanImportant
        }

        return panAbs <= maxPanDefault
    }

    private static let longClassCooldownFurniture: Set<String> = [
        "kitchen & dining room table", "couch", "chair", "bench", "plant",
    ]


    /// Picks a voice for the current "Voice" setting. "Compact" prefers small on-device (default) voices, not the soothing sort.
    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        if voices.isEmpty { return AVSpeechSynthesisVoice(language: "en-US") }
        switch VisionBridgeFeatureFlags.ttsVoiceStyle {
        case "compact":
            return preferredVoiceCompact(from: voices)
        case "clear":
            let ranked = voices.sorted(by: compareVoicesForSoothing)
            if let v = ranked.first(where: { $0.quality == .enhanced }) { return v }
            return ranked.first
        default:
            let ranked = voices.sorted(by: compareVoicesForSoothing)
            return ranked.first
        }
    }

    /// Smaller "compact" Siri-style voices: prefer lowest quality tier, then bundle ids containing "compact", then any en-US.
    private func preferredVoiceCompact(from voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        let us = voices.filter { $0.language == "en-US" }
        let pool = us.isEmpty ? voices : us
        let sorted = pool.sorted { a, b in
            if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue < b.quality.rawValue }
            let ac = a.identifier.lowercased().contains("compact")
            let bc = b.identifier.lowercased().contains("compact")
            if ac != bc { return ac && !bc }
            return a.name < b.name
        }
        if let v = sorted.first(where: { $0.quality == .default }) { return v }
        if let v = sorted.first(where: { $0.identifier.lowercased().contains("compact") }) { return v }
        if let v = sorted.first { return v }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private func voiceLanguageRank(_ lang: String) -> Int {
        if lang == "en-US" { return 0 }
        if lang == "en-GB" { return 1 }
        return 2
    }

    /// Higher score = more likely to sound soft and unhurried on-device (heuristic; `en-US` premium/enhanced still dominate).
    private func soothingTiebreakScore(_ v: AVSpeechSynthesisVoice) -> Int {
        var score = 0
        let n = v.name.lowercased()
        let softTokens = [
            "samantha", "ava", "allison", "susan", "kate", "karen", "emma", "nora", "tessa", "serena", "catherine", "fiona", "siri", "nicky"
        ]
        if softTokens.contains(where: { n.contains($0) }) { score += 4 }
        if #available(iOS 13.0, *), v.gender == .female { score += 1 }
        return score
    }

    private func compareVoicesForSoothing(_ a: AVSpeechSynthesisVoice, _ b: AVSpeechSynthesisVoice) -> Bool {
        let la = voiceLanguageRank(a.language)
        let lb = voiceLanguageRank(b.language)
        if la != lb { return la < lb }
        if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue > b.quality.rawValue }
        return soothingTiebreakScore(a) > soothingTiebreakScore(b)
    }

    private func phraseForObject(_ obj: DetectedObjectDTO, includeDistance: Bool) -> String {
        let hasKnownPhysical = VisionConfiguration.default.hasKnownPhysicalSize(for: obj.objectClass)
        let sample = DistanceFrameSample(
            objectID: obj.objectId,
            className: obj.objectClass.lowercased(),
            bbox: obj.bbox,
            rawDistanceM: obj.distanceM,
            timestamp: Date()
        )
        // If the vision pipeline supplied an explicit distance confidence (LiDAR hint), prefer it.
        let assessment: DistanceAssessment
        if let forced = obj.distanceConfidence {
            assessment = DistanceAssessment(meters: sample.rawDistanceM.isFinite ? sample.rawDistanceM : nil, confidence: forced, wasDampened: false)
        } else {
            assessment = distanceAssessor.assess(sample, hasKnownPhysicalSize: hasKnownPhysical)
        }
        if assessment.wasDampened {
            telemetryDrop(.distanceClamp, utterance: "distance-clamp:\(obj.objectId)")
        }
        if !includeDistance {
            return "\(Self.humanizeClassName(obj.objectClass)) \(directionPhrase(pan: obj.panValue))"
        }
        return phraseBuilder.phrase(
            objectClass: obj.objectClass,
            panValue: obj.panValue,
            distance: assessment,
            units: VisionBridgeFeatureFlags.distanceUnits
        )
    }

    private func telemetryDrop(_ reason: TTSDropReason, utterance: String? = nil) {
        TTSTelemetryStore.shared.record(
            TTSEvent(
                timestamp: Date(),
                utterance: utterance,
                priority: nil,
                queueDepthAtEnqueue: highPriorityStack.count + normalPriorityQueue.count,
                dropReason: reason,
                timeToSpeakMs: nil,
                voiceIdentifier: nil
            )
        )
    }

    private func directionPhrase(pan: Double) -> String {
        switch pan {
        case ..<(-0.45): return "to the left"
        case 0.45...: return "to the right"
        default: return "straight ahead"
        }
    }

    private static func humanizeClassName(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "Unknown" }
        if t.contains("_") { return t.replacingOccurrences(of: "_", with: " ") }
        return ObjectSpokenName.phrase(t)
    }

    // MARK: - AVSpeechSynthesizerDelegate
    // Keep speaking state on `workQueue` so the scheduler never calls `DispatchQueue.main.sync` (can deadlock the UI).
    func speechSynthesizer(_: AVSpeechSynthesizer, didStart _: AVSpeechUtterance) {
        workQueue.async { [weak self] in
            self?.synthesizerIsSpeaking = true
        }
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        workQueue.async { [weak self] in
            self?.synthesizerIsSpeaking = false
        }
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        workQueue.async { [weak self] in
            self?.synthesizerIsSpeaking = false
        }
    }
}
