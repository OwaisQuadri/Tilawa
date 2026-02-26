import SwiftData
import Foundation

@Model
final class RecordingSegment {
    var id: UUID?
    var recording: Recording?

    // --- Audio position within the recording file ---
    var startOffsetSeconds: Double?
    var endOffsetSeconds: Double?

    // --- Primary Quran reference ---
    var surahNumber: Int?
    var ayahNumber: Int?

    // --- Cross-surah support ---
    var endSurahNumber: Int?
    var endAyahNumber: Int?
    var isCrosssurahSegment: Bool?
    var crossSurahJoinOffsetSeconds: Double?

    // --- Quality ---
    var isManuallyAnnotated: Bool?
    var confidenceScore: Double?  // 0.0–1.0

    // --- User-defined priority ---
    var userSortOrder: Int?  // explicit priority among competing segments for same ayah+riwayah.
                             // Lower value = higher priority. nil = unset (falls back to importedAt).

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.recording = nil
        self.startOffsetSeconds = nil; self.endOffsetSeconds = nil
        self.surahNumber = nil; self.ayahNumber = nil
        self.endSurahNumber = nil; self.endAyahNumber = nil
        self.isCrosssurahSegment = nil; self.crossSurahJoinOffsetSeconds = nil
        self.isManuallyAnnotated = nil; self.confidenceScore = nil
        self.userSortOrder = nil
    }

    // MARK: - Convenience initializer
    convenience init(recording: Recording,
                     startOffset: Double, endOffset: Double,
                     surah: Int, ayah: Int) {
        self.init()
        self.id = UUID()
        self.recording = recording
        self.startOffsetSeconds = startOffset
        self.endOffsetSeconds = endOffset
        self.surahNumber = surah; self.ayahNumber = ayah
        self.endSurahNumber = surah; self.endAyahNumber = ayah
        self.isCrosssurahSegment = false
        self.isManuallyAnnotated = false
        self.confidenceScore = 0.0
    }

    // MARK: - Safe computed properties
    var safeDuration: Double { (endOffsetSeconds ?? 0) - (startOffsetSeconds ?? 0) }
    var primaryAyahRef: AyahRef { AyahRef(surah: surahNumber ?? 1, ayah: ayahNumber ?? 1) }
    var endAyahRef: AyahRef {
        AyahRef(surah: endSurahNumber ?? surahNumber ?? 1,
                ayah: endAyahNumber ?? ayahNumber ?? 1)
    }
}
