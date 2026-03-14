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
    var rangeRepeatBehavior: String?   // RangeRepeatBehavior.rawValue

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

    // --- Segment Overrides ---
    @Relationship(deleteRule: .cascade)
    var segmentOverrides: [ReciterSegmentOverride]?

    // --- Sliding Window ---
    var slidingWindowEnabled: Bool?
    var slidingWindowPreset: String?          // unused, kept for migration compat
    var slidingWindowPerAyahRepeats: Int?     // A
    var slidingWindowConnectionRepeats: Int?  // B
    var slidingWindowConnectionWindow: Int?   // C
    var slidingWindowFullRangeRepeats: Int?   // D

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
        self.rangeRepeatBehavior = nil
        self.afterRepeatAction = nil
        self.afterRepeatContinueAyaatCount = nil; self.afterRepeatContinuePagesCount = nil
        self.selectedRiwayah = nil
        self.selectedReciterId = nil
        self.reciterPriority = nil
        self.segmentOverrides = nil
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
    var safeRangeRepeatBehavior: RangeRepeatBehavior {
        RangeRepeatBehavior(rawValue: rangeRepeatBehavior ?? "") ?? .whileRepeatingAyahs
    }
    var safeSlidingWindowEnabled: Bool { slidingWindowEnabled ?? false }
    var safeSWPerAyahRepeats: Int { slidingWindowPerAyahRepeats ?? 5 }
    var safeSWConnectionRepeats: Int { slidingWindowConnectionRepeats ?? 3 }
    var safeSWConnectionWindow: Int { slidingWindowConnectionWindow ?? 2 }
    var safeSWFullRangeRepeats: Int { slidingWindowFullRangeRepeats ?? 10 }

    var sortedReciterPriority: [ReciterPriorityEntry] {
        (reciterPriority ?? [])
            .filter { $0.isEnabled ?? true }
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    /// Removes all ReciterPriorityEntry and SegmentReciterEntry items referencing `reciterId`.
    /// Call this before deleting a Reciter so stale UUID references don't accumulate.
    static func cleanupPriorityEntries(for reciterId: UUID, in context: ModelContext) {
        guard let settings = try? context.fetch(FetchDescriptor<PlaybackSettings>()).first else { return }

        let staleGlobal = (settings.reciterPriority ?? []).filter { $0.reciterId == reciterId }
        staleGlobal.forEach { context.delete($0) }
        settings.reciterPriority = (settings.reciterPriority ?? []).filter { $0.reciterId != reciterId }

        for override in settings.segmentOverrides ?? [] {
            let staleSegment = (override.reciterPriority ?? []).filter { $0.reciterId == reciterId }
            staleSegment.forEach { context.delete($0) }
            override.reciterPriority = (override.reciterPriority ?? []).filter { $0.reciterId != reciterId }
        }
    }

    /// Ensures a reciter is present in the global priority list and all segment overrides.
    /// Safe to call multiple times — no-ops if already present.
    static func ensureReciterInPriorityList(_ reciterId: UUID, context: ModelContext) {
        guard let settings = try? context.fetch(FetchDescriptor<PlaybackSettings>()).first else { return }

        let alreadyInGlobal = (settings.reciterPriority ?? []).contains { $0.reciterId == reciterId }
        if !alreadyInGlobal {
            let maxOrder = (settings.reciterPriority ?? []).compactMap { $0.order }.max() ?? -1
            let entry = ReciterPriorityEntry(order: maxOrder + 1, reciterId: reciterId)
            context.insert(entry)
            settings.reciterPriority = (settings.reciterPriority ?? []) + [entry]
        }

        for segment in settings.segmentOverrides ?? [] {
            let alreadyInSegment = (segment.reciterPriority ?? []).contains { $0.reciterId == reciterId }
            guard !alreadyInSegment else { continue }
            let maxOrder = (segment.reciterPriority ?? []).compactMap { $0.order }.max() ?? -1
            let segEntry = SegmentReciterEntry(order: maxOrder + 1, reciterId: reciterId)
            context.insert(segEntry)
            segment.reciterPriority = (segment.reciterPriority ?? []) + [segEntry]
        }

        try? context.save()
    }
}
