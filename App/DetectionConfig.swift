import Foundation

enum DetectionConfig {
    /// Classes treated as immediate mobility hazards for speech escalation.
    static let highPriorityClasses: Set<String> = [
        "person", "stairs", "chair",
    ]

    /// Reasonable operating range for monocular distance.
    static let minDistanceM: Double = 0.1
    static let maxDistanceM: Double = 60.0
}
