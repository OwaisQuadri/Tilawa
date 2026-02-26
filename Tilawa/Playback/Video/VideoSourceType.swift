import Foundation

enum VideoSourceType: String, Codable {
    case localFile    // AVPlayer with on-device file URL
    case googleDrive  // AVPlayer with authenticated Google Drive stream URL
}

/// Describes a video-backed reciter source.
/// Ayah timestamp mapping works identically to RecordingSegments.
struct VideoSource: Identifiable {
    let id: UUID
    let sourceType: VideoSourceType
    let localURL: URL?           // for localFile
    let streamURLString: String? // for googleDrive — obtained after OAuth
    var ayahMarkers: [VideoAyahMarker]

    var resolvedURL: URL? {
        switch sourceType {
        case .localFile:   return localURL
        case .googleDrive: return streamURLString.flatMap { URL(string: $0) }
        }
    }
}

/// Timestamp boundary for a single ayah within a video file.
struct VideoAyahMarker: Identifiable {
    let id: UUID
    let ayahRef: AyahRef
    let startSeconds: Double
    let endSeconds: Double

    init(ayahRef: AyahRef, startSeconds: Double, endSeconds: Double) {
        self.id = UUID()
        self.ayahRef = ayahRef
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}
