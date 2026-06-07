import Foundation

/// `UserDefaults` keys for the Settings menu. All features default **on** (first launch).
/// Settings writes these; engines read them (Hearing, haptics, HUD).
enum VisionBridgeFeatureKey {
    static let hearingTones = "bridgehax.feature.hearingTones"
    static let hearingTTS = "bridgehax.feature.hearingTTS"
    static let ttsCriticalOnly = "bridgehax.feature.ttsCriticalOnly"
    static let distanceUnits = "bridgehax.feature.distanceUnits"
    static let ttsVoiceStyle = "bridgehax.feature.ttsVoiceStyle"
    static let ttsVerbosity = "bridgehax.feature.ttsVerbosity"
    static let ttsTelemetryEnabled = "bridgehax.feature.ttsTelemetryEnabled"
    static let suppressedClassesCSV = "bridgehax.feature.suppressedClassesCSV"
    static let haptics = "bridgehax.feature.haptics"
    static let payloadHUD = "bridgehax.feature.payloadHUD"
}

enum VisionBridgeFeatureFlags {
    private static let d = UserDefaults.standard

    static var hearingTones: Bool {
        d.object(forKey: VisionBridgeFeatureKey.hearingTones) == nil ? true : d.bool(forKey: VisionBridgeFeatureKey.hearingTones)
    }

    static var hearingTTS: Bool {
        d.object(forKey: VisionBridgeFeatureKey.hearingTTS) == nil ? true : d.bool(forKey: VisionBridgeFeatureKey.hearingTTS)
    }

    static var ttsCriticalOnly: Bool {
        d.object(forKey: VisionBridgeFeatureKey.ttsCriticalOnly) == nil ? false : d.bool(forKey: VisionBridgeFeatureKey.ttsCriticalOnly)
    }

    /// "metric" (default) or "imperial"
    static var distanceUnits: String {
        let raw = d.string(forKey: VisionBridgeFeatureKey.distanceUnits)?.lowercased()
        return (raw == "imperial") ? "imperial" : "metric"
    }

    /// "calm" (default), "clear", "compact"
    static var ttsVoiceStyle: String {
        let raw = d.string(forKey: VisionBridgeFeatureKey.ttsVoiceStyle)?.lowercased()
        switch raw {
        case "clear", "compact":
            return raw ?? "calm"
        default:
            return "calm"
        }
    }

    /// "low" (default), "normal"
    static var ttsVerbosity: String {
        let raw = d.string(forKey: VisionBridgeFeatureKey.ttsVerbosity)?.lowercased()
        return (raw == "normal") ? "normal" : "low"
    }

    static var ttsTelemetryEnabled: Bool {
        d.object(forKey: VisionBridgeFeatureKey.ttsTelemetryEnabled) == nil ? false : d.bool(forKey: VisionBridgeFeatureKey.ttsTelemetryEnabled)
    }

    static var suppressedClasses: Set<String> {
        let raw = d.string(forKey: VisionBridgeFeatureKey.suppressedClassesCSV)
            ?? "clock,vase,wine glass,teddy bear,toothbrush"
        return Set(
            raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    static var haptics: Bool {
        d.object(forKey: VisionBridgeFeatureKey.haptics) == nil ? true : d.bool(forKey: VisionBridgeFeatureKey.haptics)
    }

    static var payloadHUD: Bool {
        d.object(forKey: VisionBridgeFeatureKey.payloadHUD) == nil ? false : d.bool(forKey: VisionBridgeFeatureKey.payloadHUD)
    }
}
