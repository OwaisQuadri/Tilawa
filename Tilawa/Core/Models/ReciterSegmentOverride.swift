import SwiftData
import Foundation

/// A segment-specific reciter priority override.
/// When a playback ayah falls within this range, this override's reciter
/// priority list is used instead of the global default priority.
@Model
final class ReciterSegmentOverride {
    var id: UUID?
    var startSurah: Int?
    var startAyah: Int?
    var endSurah: Int?
    var endAyah: Int?
    var order: Int?  // display order among all segment overrides

    @Relationship(inverse: \PlaybackSettings.segmentOverrides)
    var settings: PlaybackSettings?

    @Relationship(deleteRule: .cascade)
    var reciterPriority: [SegmentReciterEntry]?

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.startSurah = nil
        self.startAyah = nil
        self.endSurah = nil
        self.endAyah = nil
        self.order = nil
        self.settings = nil
        self.reciterPriority = nil
    }

    // MARK: - Convenience initializer
    convenience init(startSurah: Int, startAyah: Int, endSurah: Int, endAyah: Int, order: Int) {
        self.init()
        self.id = UUID()
        self.startSurah = startSurah
        self.startAyah = startAyah
        self.endSurah = endSurah
        self.endAyah = endAyah
        self.order = order
    }

    // MARK: - Computed

    var ayahRange: AyahRange {
        AyahRange(
            start: AyahRef(surah: startSurah ?? 1, ayah: startAyah ?? 1),
            end: AyahRef(surah: endSurah ?? 1, ayah: endAyah ?? 1)
        )
    }

    var sortedReciterPriority: [SegmentReciterEntry] {
        (reciterPriority ?? [])
            .filter { $0.isEnabled ?? true }
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }
}
