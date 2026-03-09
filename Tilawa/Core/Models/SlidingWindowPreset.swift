import SwiftData
import Foundation

/// A user-created sliding window preset with a custom name and configuration.
@Model
final class SlidingWindowPreset {
    var id: UUID?
    var name: String?
    var perAyahRepeats: Int?
    var connectionRepeats: Int?
    var connectionWindowSize: Int?
    var fullRangeRepeats: Int?
    var order: Int?

    init() {
        self.id = nil
        self.name = nil
        self.perAyahRepeats = nil
        self.connectionRepeats = nil
        self.connectionWindowSize = nil
        self.fullRangeRepeats = nil
        self.order = nil
    }

    static func make(name: String, settings: SlidingWindowSettings, order: Int = 0) -> SlidingWindowPreset {
        let p = SlidingWindowPreset()
        p.id = UUID()
        p.name = name
        p.perAyahRepeats = settings.perAyahRepeats
        p.connectionRepeats = settings.connectionRepeats
        p.connectionWindowSize = settings.connectionWindowSize
        p.fullRangeRepeats = settings.fullRangeRepeats
        p.order = order
        return p
    }

    var safeName: String { name ?? "Preset" }

    var settings: SlidingWindowSettings {
        SlidingWindowSettings(
            perAyahRepeats: perAyahRepeats ?? 5,
            connectionRepeats: connectionRepeats ?? 3,
            connectionWindowSize: connectionWindowSize ?? 2,
            fullRangeRepeats: fullRangeRepeats ?? 10
        )
    }

    /// True if this preset's values match the given settings.
    func matches(_ s: SlidingWindowSettings) -> Bool {
        (perAyahRepeats ?? 5) == s.perAyahRepeats
        && (connectionRepeats ?? 3) == s.connectionRepeats
        && (connectionWindowSize ?? 2) == s.connectionWindowSize
        && (fullRangeRepeats ?? 10) == s.fullRangeRepeats
    }
}
