import Foundation
import YouTubeKit

struct YouTubeAudioImporter {

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

    enum YouTubeImportError: LocalizedError {
        case invalidURL
        case noAudioStream
        case downloadFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Not a recognised YouTube URL. Please check the link and try again."
            case .noAudioStream:
                return "No audio stream found for this video. The video may be unavailable or age-restricted."
            case .downloadFailed(let reason):
                return "Download failed: \(reason)"
            }
        }
    }

    // MARK: - Public API

    /// Downloads the best-quality m4a audio stream for the given YouTube URL.
    ///
    /// - Parameter onTitle: Called as soon as the video's metadata resolves (before the first
    ///   byte is downloaded), so the UI can show the real title immediately.
    /// - Parameter onProgress: Called with 0…1 as bytes are written to disk.
    /// - Returns: Local temp file URL, the video ID, and the title (if metadata was available).
    func downloadAudio(
        from urlString: String,
        onTitle: @Sendable @escaping (String) -> Void = { _ in },
        onProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> (tempURL: URL, videoID: String, title: String?) {
        guard let videoID = YouTubeURLParser.extractVideoID(from: urlString) else {
            throw YouTubeImportError.invalidURL
        }

        let video = YouTube(videoID: videoID)

        // Fetch metadata and streams in parallel.
        async let metadataFetch = video.metadata
        async let streamsFetch  = video.streams
        let (metadata, streams) = try await (metadataFetch, streamsFetch)

        if let title = metadata?.title { onTitle(title) }

        guard let stream = streams
            .filterAudioOnly()
            .filter({ $0.fileExtension == .m4a })
            .highestAudioBitrateStream()
        else {
            throw YouTubeImportError.noAudioStream
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yt_\(videoID).m4a")
        try? FileManager.default.removeItem(at: tempURL)

        do {
            if let totalBytes = try await probeContentLength(for: stream.url),
               totalBytes >= Self.chunkThreshold {
                try await downloadInChunks(
                    from: stream.url, totalBytes: totalBytes,
                    to: tempURL, onProgress: onProgress)
            } else {
                try await downloadStreaming(from: stream.url, to: tempURL, onProgress: onProgress)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            if error is CancellationError { throw error }
            if let e = error as? YouTubeImportError { throw e }
            throw YouTubeImportError.downloadFailed(error.localizedDescription)
        }

        return (tempURL, videoID, metadata?.title)
    }

    // MARK: - Range support probe

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
                        throw YouTubeImportError.downloadFailed(
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

    // MARK: - Single streaming download (fallback / small files)

    private func downloadStreaming(
        from url: URL,
        to destURL: URL,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let (asyncBytes, response) = try await Self.session.bytes(from: url)
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
