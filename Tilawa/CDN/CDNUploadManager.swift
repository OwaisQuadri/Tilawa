import Foundation
import SwiftData
import UIKit

/// Orchestrates extracting per-ayah audio from recording segments and uploading to the CDN.
@Observable
@MainActor
final class CDNUploadManager {

    static let shared = CDNUploadManager()
    private init() {}

    // MARK: - Configuration

    /// Worker base URL. Replace with your deployed Worker URL.
    static let workerBaseURL = "https://tilawa-cdn.owaisquadri01.workers.dev"
    /// Upload API key. Replace with your UPLOAD_API_KEY secret value.
    static let apiKey = "si@Wo100697281"

    // MARK: - Job model

    struct UploadJob: Identifiable {
        let id: UUID
        let reciterId: UUID
        let reciterName: String
        let riwayah: Riwayah
        let totalFiles: Int
        var extractedCount: Int = 0
        var uploadedCount: Int = 0
        var phase: UploadPhase = .extracting
        var manifestURL: String?
        var baseURL: String?
        var cdnFolderId: String?
        var cdnVersion: Int?
        var cdnSourceAdded: Bool = false
        var error: String?
    }

    enum UploadPhase: String {
        case extracting, uploading, finalizing, complete, failed
    }

    private(set) var jobs: [UUID: UploadJob] = [:]

    func activeJob(for reciterId: UUID) -> UploadJob? {
        jobs.values.first { $0.reciterId == reciterId && $0.phase != .complete && $0.phase != .failed }
    }

    // MARK: - Upload

    /// Uploads all single-ayah segments for a reciter + riwayah to the CDN.
    /// Returns the job ID for tracking progress.
    @discardableResult
    func upload(
        reciter: Reciter,
        riwayah: Riwayah,
        segments: [RecordingSegment],
        context: ModelContext
    ) -> UUID {
        let jobId = UUID()
        let reciterId = reciter.id ?? UUID()

        // Filter to single-ayah segments matching the riwayah
        let eligible = segments.filter {
            $0.safeRiwayah == riwayah && $0.primaryAyahRef == $0.endAyahRef
        }

        // Look up existing cdnFolderId for this reciter+riwayah
        let existingFolderId = findExistingFolderId(reciterId: reciterId, riwayah: riwayah, context: context)

        jobs[jobId] = UploadJob(
            id: jobId,
            reciterId: reciterId,
            reciterName: reciter.safeName,
            riwayah: riwayah,
            totalFiles: eligible.count
        )

        Task {
            var bgId: UIBackgroundTaskIdentifier = .invalid
            bgId = UIApplication.shared.beginBackgroundTask(withName: "TilawaUpload-\(jobId)") {
                if bgId != .invalid { UIApplication.shared.endBackgroundTask(bgId) }
            }

            do {
                try await performUpload(
                    jobId: jobId, reciter: reciter, riwayah: riwayah,
                    segments: eligible, existingFolderId: existingFolderId, context: context
                )
            } catch {
                jobs[jobId]?.phase = .failed
                jobs[jobId]?.error = error.localizedDescription
            }

            if bgId != .invalid {
                UIApplication.shared.endBackgroundTask(bgId)
            }
        }

        return jobId
    }

    // MARK: - Private

    private func findExistingFolderId(reciterId: UUID, riwayah: Riwayah, context: ModelContext) -> String? {
        let riwayahValue = riwayah.rawValue
        let descriptor = FetchDescriptor<ReciterCDNSource>(
            predicate: #Predicate { $0.reciter?.id == reciterId && $0.riwayah == riwayahValue }
        )
        return (try? context.fetch(descriptor))?.first?.cdnFolderId
    }

    private func performUpload(
        jobId: UUID,
        reciter: Reciter,
        riwayah: Riwayah,
        segments: [RecordingSegment],
        existingFolderId: String?,
        context: ModelContext
    ) async throws {
        let extractor = SegmentAudioExtractor()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tilawa-upload-\(jobId.uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        // --- Phase 1: Extract ---
        jobs[jobId]?.phase = .extracting
        var extractedFiles: [(filename: String, url: URL)] = []

        for segment in segments {
            let url = try await extractor.extractSegment(segment, outputDirectory: tempDir)
            let filename = url.lastPathComponent
            extractedFiles.append((filename, url))
            jobs[jobId]?.extractedCount = extractedFiles.count
        }

        // --- Phase 2: Start upload session ---
        jobs[jobId]?.phase = .uploading
        let session = try await startUploadSession(
            reciterName: reciter.safeName,
            shortName: reciter.shortName,
            riwayah: riwayah.rawValue,
            style: reciter.style,
            format: "m4a",
            folderId: existingFolderId
        )

        // --- Phase 3: Upload files (8 concurrent) ---
        await withTaskGroup(of: Bool.self) { group in
            var inFlight = 0
            for (filename, fileURL) in extractedFiles {
                while inFlight >= 8 {
                    if let _ = await group.next() { inFlight -= 1 }
                }
                let sid = session.uploadId
                group.addTask { [weak self] in
                    do {
                        try await self?.uploadFile(uploadId: sid, filename: filename, fileURL: fileURL)
                        return true
                    } catch {
                        return false
                    }
                }
                inFlight += 1
            }
            for await success in group {
                if success {
                    jobs[jobId]?.uploadedCount += 1
                }
            }
        }

        // --- Phase 4: Finalize ---
        jobs[jobId]?.phase = .finalizing
        let result = try await completeUpload(uploadId: session.uploadId)
        let baseURL = "\(Self.workerBaseURL)/audio/\(session.slug)/"
        jobs[jobId]?.manifestURL = result.manifestURL
        jobs[jobId]?.baseURL = baseURL
        jobs[jobId]?.cdnFolderId = session.slug
        jobs[jobId]?.cdnVersion = result.version
        jobs[jobId]?.phase = .complete
    }

    // MARK: - Add CDN source to reciter

    func addCDNSource(jobId: UUID, reciter: Reciter, context: ModelContext) {
        guard let job = jobs[jobId], job.phase == .complete, !job.cdnSourceAdded,
              let baseURL = job.baseURL,
              let folderId = job.cdnFolderId,
              let reciterId = reciter.id else { return }

        // Match only by cdnFolderId to avoid overwriting unrelated CDN sources
        let folderDescriptor = FetchDescriptor<ReciterCDNSource>(
            predicate: #Predicate { $0.reciter?.id == reciterId && $0.cdnFolderId == folderId }
        )
        let existing = (try? context.fetch(folderDescriptor))?.first

        let updatedSource: ReciterCDNSource
        if let existing {
            existing.baseURL = baseURL
            existing.urlTemplate = nil
            existing.audioFileFormat = "m4a"
            existing.namingPatternType = ReciterNamingPattern.surahAyah.rawValue
            existing.cdnFolderId = folderId
            existing.cdnVersion = job.cdnVersion
            updatedSource = existing
        } else {
            let source = ReciterCDNSource()
            source.id = UUID()
            source.reciter = reciter
            source.baseURL = baseURL
            source.riwayah = job.riwayah.rawValue
            source.audioFileFormat = "m4a"
            source.namingPatternType = ReciterNamingPattern.surahAyah.rawValue
            source.cdnFolderId = folderId
            source.cdnVersion = job.cdnVersion
            context.insert(source)
            reciter.cdnSources = (reciter.cdnSources ?? []) + [source]
            updatedSource = source
        }

        // Clear stale cache for this specific source so files are re-downloaded from the new CDN URL
        Task {
            await AudioFileCache.shared.deleteCache(for: reciter, source: updatedSource)
        }
        updatedSource.missingAyahsJSON = nil

        try? context.save()
        jobs[jobId]?.cdnSourceAdded = true
    }

    // MARK: - API calls

    private struct StartResponse: Codable {
        let upload_id: String
        let slug: String
    }

    private struct UploadSession {
        let uploadId: String
        let slug: String
    }

    private struct CompleteResponse: Codable {
        let manifest_url: String
        let version: Int?
    }

    private struct UploadResult {
        let manifestURL: String
        let version: Int?
    }

    private func startUploadSession(
        reciterName: String,
        shortName: String?,
        riwayah: String,
        style: String?,
        format: String,
        folderId: String?
    ) async throws -> UploadSession {
        var body: [String: String] = [
            "reciter_name": reciterName,
            "riwayah": riwayah,
            "format": format,
        ]
        if let shortName { body["short_name"] = shortName }
        if let style { body["style"] = style }
        if let folderId { body["folder_id"] = folderId }

        let data = try await apiRequest(
            method: "POST",
            path: "/api/upload/start",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        let resp = try JSONDecoder().decode(StartResponse.self, from: data)
        return UploadSession(uploadId: resp.upload_id, slug: resp.slug)
    }

    private func uploadFile(uploadId: String, filename: String, fileURL: URL) async throws {
        let fileData = try Data(contentsOf: fileURL)
        _ = try await apiRequest(
            method: "PUT",
            path: "/api/upload/\(uploadId)/\(filename)",
            body: fileData,
            contentType: "audio/mp4"
        )
    }

    private func completeUpload(uploadId: String) async throws -> UploadResult {
        let data = try await apiRequest(
            method: "POST",
            path: "/api/upload/\(uploadId)/complete",
            body: nil
        )
        let resp = try JSONDecoder().decode(CompleteResponse.self, from: data)
        return UploadResult(manifestURL: resp.manifest_url, version: resp.version)
    }

    private func apiRequest(
        method: String,
        path: String,
        body: Data?,
        contentType: String = "application/json"
    ) async throws -> Data {
        var request = URLRequest(url: URL(string: Self.workerBaseURL + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(Self.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return data
    }
}
