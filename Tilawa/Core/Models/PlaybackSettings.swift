import SwiftData
import Foundation

@Model
final class PlaybackSettings {
    var id: UUID?

    // --- Playback Range ---
    var startSurah: Int?
    var startAyah: Int?
    var endSurah: Int?
    var endAyah: Int?
    var usePageRange: Bool?
    var startPage: Int?
    var endPage: Int?

    // --- Connection Ayah ---
    var connectionAyahBefore: Int?  // 0 = disabled
    var connectionAyahAfter: Int?   // 0 = disabled

    // --- Playback Control ---
    var playbackSpeed: Double?      // 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0
    var gapBetweenAyaatMs: Int?     // 0–3000 ms

    // --- Repeat ---
    var ayahRepeatCount: Int?       // 1–100, or -1 = infinite
    var rangeRepeatCount: Int?      // 1–100, or -1 = infinite

    // --- After-Range-Repeat Behavior ---
    var afterRepeatAction: String?  // AfterRepeatAction.rawValue
    var afterRepeatContinueAyaatCount: Int?
    var afterRepeatContinuePagesCount: Int?
    var afterRepeatContinuePagesExtraAyah: Bool?

    // --- Riwayah (stored as raw string for CloudKit compat) ---
    var selectedRiwayah: String?    // Riwayah.rawValue

    // --- Explicit reciter selection (nil = Auto, use full priority list) ---
    var selectedReciterId: UUID?

    // --- Reciter Priority ---
    @Relationship(deleteRule: .cascade)
    var reciterPriority: [ReciterPriorityEntry]?

    // --- Display ---
    var showRepetitionCounter: Bool?
    var showReciterName: Bool?

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.startSurah = nil; self.startAyah = nil
        self.endSurah = nil; self.endAyah = nil
        self.usePageRange = nil; self.startPage = nil; self.endPage = nil
        self.connectionAyahBefore = nil; self.connectionAyahAfter = nil
        self.playbackSpeed = nil; self.gapBetweenAyaatMs = nil
        self.ayahRepeatCount = nil; self.rangeRepeatCount = nil
        self.afterRepeatAction = nil
        self.afterRepeatContinueAyaatCount = nil; self.afterRepeatContinuePagesCount = nil
        self.selectedRiwayah = nil
        self.selectedReciterId = nil
        self.reciterPriority = nil
        self.showRepetitionCounter = nil; self.showReciterName = nil
    }

    // MARK: - Convenience initializer with defaults
    static func makeDefault() -> PlaybackSettings {
        let s = PlaybackSettings()
        s.id = UUID()
        s.playbackSpeed = 1.0
        s.gapBetweenAyaatMs = 0
        s.ayahRepeatCount = 1
        s.rangeRepeatCount = 1
        s.afterRepeatAction = AfterRepeatAction.stop.rawValue
        s.connectionAyahBefore = 0
        s.connectionAyahAfter = 0
        s.selectedRiwayah = Riwayah.hafs.rawValue
        s.usePageRange = false
        s.showRepetitionCounter = true
        s.showReciterName = true
        return s
    }

    // MARK: - Safe computed properties
    var safeSpeed: Double { playbackSpeed ?? 1.0 }
    var safeAyahRepeat: Int { ayahRepeatCount ?? 1 }
    var safeRangeRepeat: Int { rangeRepeatCount ?? 1 }
    var safeGapMs: Int { gapBetweenAyaatMs ?? 0 }
    var safeRiwayah: Riwayah { Riwayah(rawValue: selectedRiwayah ?? "") ?? .hafs }
    var safeAfterRepeatAction: AfterRepeatAction {
        AfterRepeatAction(rawValue: afterRepeatAction ?? "") ?? .stop
    }
    var sortedReciterPriority: [ReciterPriorityEntry] {
        (reciterPriority ?? [])
            .filter { $0.isEnabled ?? true }
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }
}
