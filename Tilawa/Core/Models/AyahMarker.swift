import SwiftData
import Foundation

/// Temporary annotation marker placed on the waveform during editing.
/// Converted to RecordingSegments when the user saves.
/// Persisted so the editor can be closed and reopened without losing unsaved work.
@Model
final class AyahMarker {
    var id: UUID?
    var recording: Recording?
    var positionSeconds: Double?
    var markerIndex: Int?         // display order (0 = first)
    var isConfirmed: Bool?        // true once ayah is assigned
    var assignedSurah: Int?
    var assignedAyah: Int?
    var assignedEndSurah: Int?   // optional end of ayah range (for multi-ayah segments)
    var assignedEndAyah: Int?
    var endPositionSeconds: Double?  // explicit end time; if nil, next marker's start is used

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.recording = nil
        self.positionSeconds = nil; self.markerIndex = nil
        self.isConfirmed = nil
        self.assignedSurah = nil; self.assignedAyah = nil
        self.assignedEndSurah = nil; self.assignedEndAyah = nil
        self.endPositionSeconds = nil
    }

    // MARK: - Convenience initializer
    convenience init(recording: Recording, position: Double, index: Int) {
        self.init()
        self.id = UUID()
        self.recording = recording
        self.positionSeconds = position
        self.markerIndex = index
        self.isConfirmed = false
    }

    var assignedRef: AyahRef? {
        guard let s = assignedSurah, let a = assignedAyah else { return nil }
        return AyahRef(surah: s, ayah: a)
    }
}
