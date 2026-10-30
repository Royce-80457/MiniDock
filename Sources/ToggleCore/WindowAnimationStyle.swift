import Foundation

public enum WindowAnimationStyle: String {
    case genie, scale

    /// Only known native labels. Never infer a choice from menu ordering.
    public init?(systemLabel: String) {
        switch systemLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "神奇效果", "genie effect": self = .genie
        case "缩放效果", "scale effect": self = .scale
        default: return nil
        }
    }
    public var title: String {
        switch self { case .genie: return "神奇效果"; case .scale: return "缩放效果" }
    }
}
