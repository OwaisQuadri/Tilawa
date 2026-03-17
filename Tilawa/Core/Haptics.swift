import UIKit

/// Centralized haptic feedback helper that respects the user's toggle.
enum Haptics {

    private static let key = "settings.hapticsEnabled"

    /// `true` when haptics are enabled (default: on).
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) == nil
            || UserDefaults.standard.bool(forKey: key)
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
