import Foundation

/// Tracks the live state of a single in-progress or failed generic URL audio import.
@Observable
final class URLImportTask: Identifiable, @unchecked Sendable {

    let id = UUID()
    let urlString: String
    /// Set once response headers are parsed at the start of the download.
    var title: String?

    var state: ImportState = .downloading(progress: 0)

    enum ImportState {
        case downloading(progress: Double)  // 0…1; 0 = indeterminate
        case failed(String)
    }

    /// Human-readable title: prefers the resolved filename, falls back to the URL string.
    var displayTitle: String { title ?? urlString }

    init(urlString: String) {
        self.urlString = urlString
    }
}
