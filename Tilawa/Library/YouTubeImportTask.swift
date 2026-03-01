import Foundation

/// Tracks the live state of a single in-progress or failed YouTube audio import.
@Observable
final class YouTubeImportTask: Identifiable, @unchecked Sendable {

    let id = UUID()
    let urlString: String
    /// Extracted immediately on creation; used as fallback title until metadata arrives.
    let videoID: String
    /// Set once `YouTube.metadata` resolves at the start of the download.
    var title: String?

    var state: ImportState = .downloading(progress: 0)

    enum ImportState {
        case downloading(progress: Double)  // 0…1; 0 = indeterminate
        case failed(String)
    }

    /// Human-readable title: prefers the fetched metadata title, falls back to the video ID.
    var displayTitle: String { title ?? videoID }

    init(urlString: String) {
        self.urlString = urlString
        self.videoID = YouTubeURLParser.extractVideoID(from: urlString) ?? urlString
    }
}
