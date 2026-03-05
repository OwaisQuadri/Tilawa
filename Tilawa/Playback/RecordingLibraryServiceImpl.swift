import Foundation
import SwiftData

/// Full SwiftData implementation of RecordingLibraryService.
///
/// Holds a ModelContainer (Sendable) and creates a fresh background ModelContext per query
/// to avoid threading issues — the same pattern used by AudioFileCache and other services.
final class RecordingLibraryServiceImpl: RecordingLibraryService, @unchecked Sendable {

    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func segments(for ref: AyahRef, reciter: Reciter) async -> [RecordingSegment] {
        let ctx = ModelContext(container)
        let surah = ref.surah
        let ayah  = ref.ayah

        // Fetch 1: segments whose start surah matches.
        let startDesc = FetchDescriptor<RecordingSegment>(
            predicate: #Predicate { $0.surahNumber == surah }
        )
        let startMatches = (try? ctx.fetch(startDesc)) ?? []

        // Fetch 2: cross-surah segments that end in this surah (start is in an earlier surah).
        // Range predicates on optional Int fields aren't reliably supported in SwiftData
        // #Predicate, so we use a separate fetch and filter in memory.
        let endDesc = FetchDescriptor<RecordingSegment>(
            predicate: #Predicate { $0.endSurahNumber == surah }
        )
        let endMatches = (try? ctx.fetch(endDesc)) ?? []

        var seen = Set<PersistentIdentifier>()
        let inRange: [RecordingSegment] = (startMatches + endMatches).filter { seg in
            guard seen.insert(seg.persistentModelID).inserted else { return false }
            guard let startAyah = seg.ayahNumber else { return false }
            let segStartSurah = seg.surahNumber ?? surah
            let endSurah = seg.endSurahNumber ?? segStartSurah
            let endAyah  = seg.endAyahNumber  ?? startAyah

            if segStartSurah == surah && endSurah == surah {
                // Same-surah segment: ayah must fall within [startAyah, endAyah]
                return startAyah <= ayah && ayah <= endAyah
            } else if segStartSurah == surah {
                // Cross-surah segment queried at its start surah: ref must be at or after start
                return startAyah <= ayah
            } else {
                // Cross-surah segment queried at its end surah: ref must be at or before end
                return ayah <= endAyah
            }
        }

        guard !inRange.isEmpty, let reciterId = reciter.id else { return inRange }
        return inRange.filter { $0.reciter?.id == reciterId }
    }
}
