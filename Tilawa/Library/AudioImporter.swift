import Foundation
import AVFoundation
import SwiftData
import UniformTypeIdentifiers

/// Handles two sources of user-generated audio content:
///   1. Local audio files (copy to Documents/TilawaRecordings/)
///   2. Video files (extract audio track → m4a, store in Documents/TilawaRecordings/)
@MainActor
final class AudioImporter {

    // MARK: - Supported types

    static let supportedAudioTypes: [UTType] = [
        .mp3, .mpeg4Audio, .wav, .aiff,
        UTType(mimeType: "audio/flac") ?? .audio,
        UTType(mimeType: "audio/ogg") ?? .audio,
        UTType(mimeType: "audio/opus") ?? .audio,
    ].filter { $0 != .audio }  // drop any fallbacks that resolved to .audio generic

    static let supportedVideoTypes: [UTType] = [
        .mpeg4Movie, .quickTimeMovie,
        UTType("public.m4v-video") ?? .movie,
    ].filter { $0 != .movie }

    // MARK: - Storage

    static var recordingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("TilawaRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Import audio file

    /// Copies a security-scoped audio file URL into the app's recordings directory,
    /// creates a Recording model, and returns it.
    func importAudioFile(at url: URL, context: ModelContext) async throws -> Recording {
        defer { url.stopAccessingSecurityScopedResource() }

        let fileExt = url.pathExtension.lowercased()
        let recordingId = UUID()
        let filename = "\(recordingId.uuidString).\(fileExt)"
        let destURL = Self.recordingsDirectory.appendingPathComponent(filename)

        try FileManager.default.copyItem(at: url, to: destURL)

        let duration = await loadDuration(url: destURL)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int) ?? 0

        let recording = Recording(title: url.deletingPathExtension().lastPathComponent,
                                  storagePath: filename)
        recording.id = recordingId
        recording.sourceFileName = url.lastPathComponent
        recording.durationSeconds = duration
        recording.fileFormat = fileExt
        recording.fileSizeBytes = fileSize
        // reciter defaults to nil — user assigns one in RecordingDetailView

        context.insert(recording)
        try context.save()
        return recording
    }

    // MARK: - Import video file (extract audio)

    /// Extracts the audio track from a video file and saves it as .m4a.
    func importVideoFile(at url: URL, context: ModelContext) async throws -> Recording {
        defer { url.stopAccessingSecurityScopedResource() }

        let recordingId = UUID()
        let filename = "\(recordingId.uuidString).m4a"
        let destURL = Self.recordingsDirectory.appendingPathComponent(filename)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(recordingId.uuidString)_export.m4a")

        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetAppleM4A) else {
            throw ImportError.exportSessionCreationFailed
        }
        session.outputFileType = .m4a
        session.outputURL = tempURL

        await session.export()

        guard session.status == .completed else {
            throw ImportError.exportFailed(session.error?.localizedDescription ?? "Unknown")
        }

        try FileManager.default.moveItem(at: tempURL, to: destURL)

        let duration = await loadDuration(url: destURL)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int) ?? 0

        let title = url.deletingPathExtension().lastPathComponent

        let recording = Recording(title: title, storagePath: filename)
        recording.id = recordingId
        recording.sourceFileName = url.lastPathComponent
        recording.durationSeconds = duration
        recording.fileFormat = "m4a"
        recording.fileSizeBytes = fileSize
        // reciter defaults to nil — user assigns one in RecordingDetailView

        context.insert(recording)
        try context.save()
        return recording
    }

    // MARK: - Helpers

    private func loadDuration(url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : nil
    }
}

// MARK: - Errors

enum ImportError: LocalizedError {
    case exportSessionCreationFailed
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .exportSessionCreationFailed:
            return "Could not create audio export session for this video."
        case .exportFailed(let reason):
            return "Audio extraction failed: \(reason)"
        }
    }
}
