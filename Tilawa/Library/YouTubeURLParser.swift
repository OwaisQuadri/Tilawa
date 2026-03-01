import Foundation

/// Parses YouTube video IDs from the various URL formats YouTube produces.
///
/// Supported formats:
/// - `https://www.youtube.com/watch?v=QdXU_13OU5o&list=...`
/// - `https://youtu.be/QdXU_13OU5o?list=...`
/// - `https://youtu.be/QdXU_13OU5o?si=...`
struct YouTubeURLParser {

    /// Extracts the video ID from a YouTube URL string, or returns nil if unrecognised.
    static func extractVideoID(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host else { return nil }

        // youtu.be/<videoID>
        if host == "youtu.be" {
            let id = url.pathComponents.dropFirst().first
            return validated(id)
        }

        // www.youtube.com/watch?v=<videoID>  (also m.youtube.com, music.youtube.com)
        if host.hasSuffix("youtube.com") {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let id = components?.queryItems?.first(where: { $0.name == "v" })?.value
            return validated(id)
        }

        return nil
    }

    // YouTube video IDs are always 11 characters (alphanumeric + - _).
    private static func validated(_ id: String?) -> String? {
        guard let id,
              id.count == 11,
              id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { return nil }
        return id
    }
}
