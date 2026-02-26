import SwiftData
import Foundation

@Model
final class Recording {
    var id: UUID?
    var title: String?
    var sourceFileName: String?
    /// Relative path within iCloud ubiquity container.
    var storagePath: String?
    var durationSeconds: Double?
    var fileFormat: String?           // "m4a" | "mp3" | "wav" | "caf"
    var fileSizeBytes: Int?
    var importedAt: Date?
    var recordedAt: Date?
    var annotationStatus: String?     // AnnotationStatus.rawValue
    var notes: String?

    // Denormalized coverage cache
    var coversSurahStart: Int?
    var coversSurahEnd: Int?

    var reciter: Reciter?

    @Relationship(deleteRule: .cascade)
    var segments: [RecordingSegment]?

    @Relationship(deleteRule: .cascade)
    var markers: [AyahMarker]?

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.title = nil; self.sourceFileName = nil; self.storagePath = nil
        self.durationSeconds = nil; self.fileFormat = nil; self.fileSizeBytes = nil
        self.importedAt = nil; self.recordedAt = nil
        self.annotationStatus = nil; self.notes = nil
        self.coversSurahStart = nil; self.coversSurahEnd = nil
        self.reciter = nil; self.segments = nil; self.markers = nil
    }

    // MARK: - Convenience initializer
    convenience init(title: String, storagePath: String) {
        self.init()
        self.id = UUID()
        self.title = title
        self.storagePath = storagePath
        self.importedAt = Date()
        self.annotationStatus = AnnotationStatus.unannotated.rawValue
    }

    // MARK: - Safe computed properties
    var safeTitle: String { title ?? "Untitled Recording" }
    var safeDuration: Double { durationSeconds ?? 0 }
    var annotationStatusEnum: AnnotationStatus {
        AnnotationStatus(rawValue: annotationStatus ?? "") ?? .unannotated
    }
    var sortedSegments: [RecordingSegment] {
        (segments ?? []).sorted { ($0.startOffsetSeconds ?? 0) < ($1.startOffsetSeconds ?? 0) }
    }
}
