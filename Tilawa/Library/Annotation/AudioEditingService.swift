import Foundation
import AVFoundation

/// Performs destructive audio-file edits (delete region, crop, finalize)
/// using AVMutableComposition + AVAssetExportSession.
actor AudioEditingService {

    enum EditError: LocalizedError {
        case noAudioTrack
        case exportSessionFailed
        case exportFailed(String)
        case invalidTimeRange

        var errorDescription: String? {
            switch self {
            case .noAudioTrack:         return "No audio track found in the recording."
            case .exportSessionFailed:  return "Could not create audio export session."
            case .exportFailed(let r):  return "Audio export failed: \(r)"
            case .invalidTimeRange:     return "The selected time range is invalid."
            }
        }
    }

    /// Deletes the region [start, end) from the audio file.
    /// Returns the new file duration.
    func deleteRegion(fileURL: URL, start: Double, end: Double) async throws -> Double {
        guard start < end else { throw EditError.invalidTimeRange }

        let asset = AVURLAsset(url: fileURL)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw EditError.noAudioTrack }

        let totalDuration = CMTimeGetSeconds(duration)
        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw EditError.exportSessionFailed }

        // Insert audio BEFORE the cut
        if start > 0 {
            let beforeRange = CMTimeRange(
                start: .zero,
                end: CMTime(seconds: start, preferredTimescale: 44100)
            )
            try compTrack.insertTimeRange(beforeRange, of: track, at: .zero)
        }

        // Insert audio AFTER the cut
        if end < totalDuration {
            let afterRange = CMTimeRange(
                start: CMTime(seconds: end, preferredTimescale: 44100),
                end: duration
            )
            let insertAt = CMTime(seconds: start, preferredTimescale: 44100)
            try compTrack.insertTimeRange(afterRange, of: track, at: insertAt)
        }

        try await exportAndReplace(composition: composition, originalURL: fileURL)
        return totalDuration - (end - start)
    }

    /// Crops the audio file to keep only [start, end).
    /// Returns the new file duration.
    func cropToRegion(fileURL: URL, start: Double, end: Double) async throws -> Double {
        guard start < end else { throw EditError.invalidTimeRange }

        let asset = AVURLAsset(url: fileURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw EditError.noAudioTrack }

        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw EditError.exportSessionFailed }

        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 44100),
            end: CMTime(seconds: end, preferredTimescale: 44100)
        )
        try compTrack.insertTimeRange(range, of: track, at: .zero)

        try await exportAndReplace(composition: composition, originalURL: fileURL)
        return end - start
    }

    /// Keeps only the time ranges covered by segments, concatenated in order.
    /// Returns (newDuration, offsetMapping) where each mapping entry describes
    /// how an old time range maps to its new position.
    func finalize(
        fileURL: URL,
        segmentRanges: [(start: Double, end: Double)]
    ) async throws -> (Double, [(oldStart: Double, newStart: Double, oldEnd: Double, newEnd: Double)]) {
        guard !segmentRanges.isEmpty else { throw EditError.invalidTimeRange }

        let asset = AVURLAsset(url: fileURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw EditError.noAudioTrack }

        let sorted = segmentRanges.sorted { $0.start < $1.start }

        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw EditError.exportSessionFailed }

        var mapping: [(oldStart: Double, newStart: Double, oldEnd: Double, newEnd: Double)] = []
        var insertionPoint: Double = 0

        for range in sorted {
            let cmRange = CMTimeRange(
                start: CMTime(seconds: range.start, preferredTimescale: 44100),
                end: CMTime(seconds: range.end, preferredTimescale: 44100)
            )
            try compTrack.insertTimeRange(
                cmRange, of: track,
                at: CMTime(seconds: insertionPoint, preferredTimescale: 44100)
            )
            let segDuration = range.end - range.start
            mapping.append((range.start, insertionPoint, range.end, insertionPoint + segDuration))
            insertionPoint += segDuration
        }

        try await exportAndReplace(composition: composition, originalURL: fileURL)
        return (insertionPoint, mapping)
    }

    // MARK: - Internal

    /// Exports composition to a temp file and atomically replaces the original.
    /// Always outputs .m4a regardless of original format.
    private func exportAndReplace(composition: AVMutableComposition, originalURL: URL) async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else { throw EditError.exportSessionFailed }

        session.outputFileType = .m4a
        session.outputURL = tempURL

        await session.export()

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: tempURL)
            throw EditError.exportFailed(session.error?.localizedDescription ?? "Unknown error")
        }

        // Remove original and move exported file into place.
        // Destination always uses .m4a extension.
        let destURL = originalURL.deletingPathExtension().appendingPathExtension("m4a")
        try FileManager.default.removeItem(at: originalURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
    }
}
