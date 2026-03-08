import SwiftData
import SwiftUI
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
    var reciterID: UUID?             // reciter to assign to the segment opening at this marker
    var riwayah: String?             // Riwayah.rawValue — riwayah for the segment opening at this marker
    var markerType: String?          // "ayah" | "cropAfter" | "cropBefore"; nil = "ayah"

    enum MarkerType: String, CaseIterable {
        case ayah = "ayah"
        case cropAfter = "cropAfter"
        case cropBefore = "cropBefore"
    }

    var resolvedMarkerType: MarkerType {
        MarkerType(rawValue: markerType ?? "") ?? .ayah
    }

    var displayColor: Color {
        switch resolvedMarkerType {
        case .cropAfter, .cropBefore: return .purple
        case .ayah: return (isConfirmed == true) ? .green : .orange
        }
    }

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.recording = nil
        self.positionSeconds = nil; self.markerIndex = nil
        self.isConfirmed = nil
        self.assignedSurah = nil; self.assignedAyah = nil
        self.assignedEndSurah = nil; self.assignedEndAyah = nil
        self.endPositionSeconds = nil
        self.reciterID = nil
        self.riwayah = nil
        self.markerType = nil
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
