import Foundation

/// Provides access to user-imported recordings for a specific ayah + reciter.
/// The concrete SwiftData implementation will be added alongside the UGC system.
protocol RecordingLibraryService: Sendable {
    func segments(for ref: AyahRef, reciter: Reciter) async -> [RecordingSegment]
}

/// Stub implementation — returns empty until UGC recording system is built.
final class StubRecordingLibraryService: RecordingLibraryService, Sendable {
    func segments(for ref: AyahRef, reciter: Reciter) async -> [RecordingSegment] { [] }
}
