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
        let ayah = ref.ayah
        let descriptor = FetchDescriptor<RecordingSegment>(
            predicate: #Predicate { $0.surahNumber == surah && $0.ayahNumber == ayah }
        )
        let all = (try? ctx.fetch(descriptor)) ?? []
        // Multi-hop optional chains (seg.recording?.reciter?.id) aren't reliable in #Predicate,
        // so filter in-memory on the small result set.
        return all.filter { $0.recording?.reciter?.id == reciter.id }
    }
}
