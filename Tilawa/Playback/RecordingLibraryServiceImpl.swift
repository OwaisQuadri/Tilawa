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
        // Fetch all segments in this surah, then filter in-memory for range containment.
        // A simple startAyah == ayah predicate misses multi-ayah segments when playback
        // starts mid-segment (e.g. after a seek). Range predicates on optional Int fields
        // aren't reliably supported in SwiftData #Predicate, so we filter in memory.
        let descriptor = FetchDescriptor<RecordingSegment>(
            predicate: #Predicate { $0.surahNumber == surah }
        )
        let all = (try? ctx.fetch(descriptor)) ?? []
        let inRange = all.filter { seg in
            guard let startAyah = seg.ayahNumber else { return false }
            let endSurah = seg.endSurahNumber ?? surah
            let endAyah  = seg.endAyahNumber  ?? startAyah
            // Only match same-surah segments (cross-surah segments handled by their start surah)
            guard endSurah == surah else { return false }
            return startAyah <= ayah && ayah <= endAyah
        }
        guard !inRange.isEmpty, let reciterId = reciter.id else { return inRange }
        // Filter by reciter using a forward @Relationship chain instead of the back-reference
        // seg.recording?.reciter?.id, which is unreliable in a background ModelContext.
        // Fetch the reciter in this context, then walk reciter → recordings → segments
        // (all @Relationship-decorated forward links) to build a set of valid segment IDs.
        let reciterDesc = FetchDescriptor<Reciter>(predicate: #Predicate { $0.id == reciterId })
        guard let bgReciter = (try? ctx.fetch(reciterDesc))?.first else { return inRange }
        let validSegIDs = Set(
            (bgReciter.recordings ?? []).flatMap { $0.segments ?? [] }.map { $0.persistentModelID }
        )
        guard !validSegIDs.isEmpty else { return inRange }
        return inRange.filter { validSegIDs.contains($0.persistentModelID) }
    }
}
