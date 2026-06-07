import UIKit

/**
 * Bridge Haptic Manager
 *
 * For visually impaired users, haptics are the physical UI.
 * Patterns reflect object proximity and priority.
 */
class HapticManager {
    static let shared = HapticManager()
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    
    private init() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        notification.prepare()
    }

    private static var hapticsOn: Bool {
        let d = UserDefaults.standard
        if d.object(forKey: VisionBridgeFeatureKey.haptics) == nil { return true }
        return d.bool(forKey: VisionBridgeFeatureKey.haptics)
    }
    
    /// Triggered when a new object enters the radar
    func triggerDiscovery() {
        guard Self.hapticsOn else { return }
        impactLight.impactOccurred()
    }
    
    /// Triggered when an object enters the 'Warning' zone (< 5m)
    func triggerWarning() {
        guard Self.hapticsOn else { return }
        impactMedium.impactOccurred()
    }
    
    /// Triggered for critical proximity or collision threats (< 2m)
    func triggerCriticalThreat() {
        guard Self.hapticsOn else { return }
        notification.notificationOccurred(.error)
        impactHeavy.impactOccurred()
    }
    
    /// Haptic 'Heartbeat' that increases in frequency as threats approach
    func triggerHeartbeat(intensity: CGFloat) {
        guard Self.hapticsOn else { return }
        // Implementation would use Core Haptics for custom CHHapticPattern
        impactLight.impactOccurred(intensity: intensity)
    }
}
