import Foundation

struct GenericURLImporter {

    // MARK: - Configuration

    private static let chunkThreshold: Int64 = 5 * 1024 * 1024   // 5 MB
    private static let chunkCount = 8
    private static let bufferSize = 256 * 1024                    // 256 KB

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: config)
    }()

    // MARK: - Errors

    enum URLImportError: LocalizedError {
        case invalidURL
        case downloadFailed(String)
        case unsupportedContentType(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Not a valid URL. Please check the link and try again."
            case .downloadFailed(let reason):
                return "Download failed: \(reason)"
            case .unsupportedContentType(let type):
                return "Unsupported content type '\(type)'. Only audio and video files are supported."
            }
        }
    }

    // MARK: - Public API

    /// Downloads audio or video from any direct URL.
    ///
    /// - Parameter onTitle: Called once the filename/title is resolved from response headers.
    /// - Parameter onProgress: Called with 0…1 as bytes are written to disk.
    /// - Returns: Local temp file URL, optional title, and whether the file is video (needs audio extraction).
    func downloadMedia(
        from urlString: String,
        onTitle: @Sendable @escaping (String) -> Void = { _ in },
        onProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> (tempURL: URL, title: String?, isVideo: Bool) {
        guard let rawURL = URL(string: urlString),
              let scheme = rawURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw URLImportError.invalidURL
        }

        // Rewrite known detail-page URLs to their direct download equivalents.
        let url = Self.resolveDirectDownloadURL(rawURL)

        // Probe via Range request to get Content-Type, Content-Length, Content-Disposition.
        let (contentType, contentLength, disposition) = await probeURL(url)

        // Determine media type from Content-Type header, falling back to URL extension.
        let urlExt = url.pathExtension.lowercased()
        let videoContentType = contentType.hasPrefix("video/")
        let audioContentType = contentType.hasPrefix("audio/")
        let videoExts: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]
        let audioExts: Set<String> = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aac", "aiff", "caf"]
        let isVideoFile = videoContentType || (!audioContentType && videoExts.contains(urlExt))
        let isKnownType = audioContentType || videoContentType
            || audioExts.contains(urlExt) || videoExts.contains(urlExt)
            || contentType.contains("octet-stream") || contentType.isEmpty

        if !isKnownType {
            throw URLImportError.unsupportedContentType(contentType)
        }

        // Derive a human-readable title.
        let title = extractTitle(from: disposition, url: url)
        if let title { onTitle(title) }

        // Choose file extension for the temp file.
        let fileExt: String
        if !urlExt.isEmpty {
            fileExt = urlExt
        } else if isVideoFile {
            fileExt = "mp4"
        } else {
            fileExt = "mp3"
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("url_import_\(UUID().uuidString).\(fileExt)")
        try? FileManager.default.removeItem(at: tempURL)

        do {
            if let total = contentLength, total >= Self.chunkThreshold {
                try await downloadInChunks(
                    from: url, totalBytes: total, to: tempURL, onProgress: onProgress)
            } else {
                try await downloadStreaming(from: url, to: tempURL, onProgress: onProgress)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            if error is CancellationError { throw error }
            if let e = error as? URLImportError { throw e }
            throw URLImportError.downloadFailed(error.localizedDescription)
        }

        return (tempURL, title, isVideoFile)
    }

    // MARK: - URL probe

    /// Sends a Range: bytes=0-0 request to read Content-Type, Content-Length, and Content-Disposition
    /// without downloading the whole file. Returns empty strings / nil if the server doesn't cooperate.
    private func probeURL(_ url: URL) async -> (contentType: String, contentLength: Int64?, disposition: String) {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.timeoutInterval = 15

        guard let (_, response) = try? await Self.session.data(for: request),
              let http = response as? HTTPURLResponse else {
            return ("", nil, "")
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        let disposition = http.value(forHTTPHeaderField: "Content-Disposition") ?? ""

        // Content-Length from Content-Range: bytes 0-0/TOTAL
        var contentLength: Int64?
        if http.statusCode == 206,
           let rangeHeader = http.value(forHTTPHeaderField: "Content-Range"),
           let totalStr = rangeHeader.split(separator: "/").last,
           let total = Int64(totalStr), total > 0 {
            contentLength = total
        } else if http.statusCode == 200 {
            let len = http.expectedContentLength
            if len > 0 { contentLength = len }
        }

        return (contentType.lowercased(), contentLength, disposition)
    }

    // MARK: - URL normalisation

    /// Rewrites known "detail page" URLs to their direct download equivalents so
    /// the download step doesn't land on an HTML page.
    ///
    /// Currently handles:
    /// - **archive.org**: `/details/IDENTIFIER/FILE` → `/download/IDENTIFIER/FILE`
    private static func resolveDirectDownloadURL(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              host == "archive.org" || host == "www.archive.org" else { return url }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let path = components?.path, path.hasPrefix("/details/") else { return url }

        components?.path = "/download/" + path.dropFirst("/details/".count)
        return components?.url ?? url
    }

    // MARK: - Title extraction

    private func extractTitle(from disposition: String, url: URL) -> String? {
        if !disposition.isEmpty {
            let parts = disposition.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            for part in parts {
                // RFC 5987 extended value: filename*=UTF-8''encoded-name
                if part.lowercased().hasPrefix("filename*=") {
                    let value = String(part.dropFirst("filename*=".count))
                    if let encoded = value.components(separatedBy: "''").last,
                       let decoded = encoded.removingPercentEncoding,
                       !decoded.isEmpty {
                        return URL(fileURLWithPath: decoded).deletingPathExtension().lastPathComponent
                    }
                }
                // Regular: filename="foo.mp3"
                if part.lowercased().hasPrefix("filename=") {
                    let name = String(part.dropFirst("filename=".count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !name.isEmpty {
                        return URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
                    }
                }
            }
        }
        // Fall back to the URL's last path component.
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? nil : name
    }

    // MARK: - Range support probe (for chunk decisions)

    private func probeContentLength(for url: URL) async throws -> Int64? {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 206,
              let rangeHeader = http.value(forHTTPHeaderField: "Content-Range"),
              let totalStr = rangeHeader.split(separator: "/").last,
              let total = Int64(totalStr), total > 0
        else { return nil }
        return total
    }

    // MARK: - Parallel chunked download

    private func downloadInChunks(
        from url: URL,
        totalBytes: Int64,
        to destURL: URL,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        FileManager.default.createFile(atPath: destURL.path, contents: nil)
        let setupHandle = try FileHandle(forWritingTo: destURL)
        try setupHandle.truncate(atOffset: UInt64(totalBytes))
        try setupHandle.close()

        let n = Self.chunkCount
        let chunkSize = (totalBytes + Int64(n) - 1) / Int64(n)
        let tracker = DownloadProgressTracker(
            chunkCount: n, totalBytes: totalBytes, onProgress: onProgress)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<n {
                let start = Int64(i) * chunkSize
                let end   = min(start + chunkSize - 1, totalBytes - 1)

                group.addTask {
                    var request = URLRequest(url: url)
                    request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")

                    let (asyncBytes, response) = try await Self.session.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 206 else {
                        throw URLImportError.downloadFailed(
                            "Server rejected range request for chunk \(i).")
                    }

                    let fh = try FileHandle(forWritingTo: destURL)
                    try fh.seek(toOffset: UInt64(start))

                    var buffer = Data(capacity: Self.bufferSize)
                    var written: Int64 = 0

                    for try await byte in asyncBytes {
                        buffer.append(byte)
                        if buffer.count >= Self.bufferSize {
                            fh.write(buffer)
                            written += Int64(buffer.count)
                            buffer.removeAll(keepingCapacity: true)
                            await tracker.update(chunk: i, bytesWritten: written)
                        }
                    }
                    if !buffer.isEmpty {
                        fh.write(buffer)
                        written += Int64(buffer.count)
                    }
                    try fh.close()
                    await tracker.update(chunk: i, bytesWritten: written)
                }
            }
            try await group.waitForAll()
        }
        onProgress(1.0)
    }

    // MARK: - Single streaming download (fallback / small files / no range support)

    private func downloadStreaming(
        from url: URL,
        to destURL: URL,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let (asyncBytes, response) = try await Self.session.bytes(from: url)

        // Verify the actual response (after all redirects) is media, not an HTML page.
        if let http = response as? HTTPURLResponse {
            let finalCT = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            if finalCT.hasPrefix("text/") {
                throw URLImportError.downloadFailed(
                    "The URL returned a web page instead of an audio or video file. Try using the direct download link.")
            }
        }

        let expectedLength = response.expectedContentLength

        FileManager.default.createFile(atPath: destURL.path, contents: nil)
        let fh = try FileHandle(forWritingTo: destURL)

        var bytesReceived: Int64 = 0
        var buffer = Data(capacity: Self.bufferSize)

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= Self.bufferSize {
                fh.write(buffer)
                bytesReceived += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expectedLength > 0 {
                    onProgress(min(1.0, Double(bytesReceived) / Double(expectedLength)))
                }
            }
        }
        if !buffer.isEmpty { fh.write(buffer) }
        if expectedLength > 0 { onProgress(1.0) }
        try fh.close()
    }
}

// MARK: - Progress tracker

private actor DownloadProgressTracker {
    private var bytesWritten: [Int64]
    private let totalBytes: Int64
    private let onProgress: @Sendable (Double) -> Void

    init(chunkCount: Int, totalBytes: Int64, onProgress: @Sendable @escaping (Double) -> Void) {
        self.bytesWritten = Array(repeating: 0, count: chunkCount)
        self.totalBytes   = totalBytes
        self.onProgress   = onProgress
    }

    func update(chunk: Int, bytesWritten bytes: Int64) {
        bytesWritten[chunk] = bytes
        let completed = bytesWritten.reduce(0, +)
        onProgress(min(1.0, Double(completed) / Double(totalBytes)))
    }
}
