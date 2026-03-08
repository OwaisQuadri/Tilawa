import AVFoundation
import Foundation

/// Extracts individual ayah audio files from recording segments using AVAssetExportSession.
@MainActor
final class SegmentAudioExtractor {

    enum ExtractionError: LocalizedError {
        case recordingPathMissing
        case recordingFileNotFound(String)
        case exportSessionFailed
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .recordingPathMissing:
                return "Recording has no storage path."
            case .recordingFileNotFound(let path):
                return "Recording file not found at \(path)."
            case .exportSessionFailed:
                return "Could not create audio export session."
            case .exportFailed(let reason):
                return "Audio extraction failed: \(reason)"
            }
        }
    }

    /// Extracts a single segment from its parent recording as a standalone .m4a file.
    /// Returns the URL of the extracted file in `outputDirectory`.
    func extractSegment(
        _ segment: RecordingSegment,
        outputDirectory: URL
    ) async throws -> URL {
        guard let storagePath = segment.recording?.storagePath else {
            throw ExtractionError.recordingPathMissing
        }

        let recordingURL = AudioImporter.recordingsDirectory
            .appendingPathComponent(storagePath)

        guard FileManager.default.fileExists(atPath: recordingURL.path) else {
            throw ExtractionError.recordingFileNotFound(storagePath)
        }

        let surah = segment.surahNumber ?? 1
        let ayah = segment.ayahNumber ?? 1
        let filename = String(format: "%03d%03d.m4a", surah, ayah)
        let outputURL = outputDirectory.appendingPathComponent(filename)

        // Remove any existing file at the output path
        try? FileManager.default.removeItem(at: outputURL)

        let asset = AVURLAsset(url: recordingURL)

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ExtractionError.exportSessionFailed
        }

        let start = CMTime(seconds: segment.startOffsetSeconds ?? 0, preferredTimescale: 44100)
        let end = CMTime(seconds: segment.endOffsetSeconds ?? 0, preferredTimescale: 44100)
        session.timeRange = CMTimeRange(start: start, end: end)
        session.outputFileType = .m4a
        session.outputURL = outputURL

        await session.export()

        guard session.status == .completed else {
            throw ExtractionError.exportFailed(
                session.error?.localizedDescription ?? "Unknown error"
            )
        }

        return outputURL
    }

    /// Generates the CDN filename for a segment.
    static func cdnFilename(surah: Int, ayah: Int) -> String {
        String(format: "%03d%03d.m4a", surah, ayah)
    }
}
