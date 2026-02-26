import Foundation
import SwiftData
import UserNotifications
import UIKit

/// Manages bulk surah downloads for CDN reciters.
/// Downloads run in parallel (up to 4 surahs concurrently), survive view dismissal,
/// and fire a local notification when complete.
@Observable
@MainActor
final class DownloadManager {

    static let shared = DownloadManager()
    private init() {}

    // MARK: - Job model

    struct DownloadJob: Identifiable {
        let id: UUID
        let reciterId: UUID
        let reciterName: String
        let totalSurahCount: Int
        var surahProgress: [Int: Double] = [:]  // surah → 0.0–1.0
        var failedSurahs: Set<Int> = []

        var completedCount: Int { surahProgress.values.filter { $0 >= 1.0 }.count }

        var overall: Double {
            guard totalSurahCount > 0 else { return 1.0 }
            return Double(completedCount + failedSurahs.count) / Double(totalSurahCount)
        }

        var isDone: Bool { completedCount + failedSurahs.count == totalSurahCount }

        var statusText: String {
            if isDone {
                return failedSurahs.isEmpty
                    ? "\(completedCount)/\(totalSurahCount) surahs downloaded"
                    : "\(completedCount) done, \(failedSurahs.count) failed"
            }
            return "Downloading \(completedCount)/\(totalSurahCount)…"
        }
    }

    // jobId → job (jobs stay for 4 s after completion so the UI can read final state)
    private(set) var jobs: [UUID: DownloadJob] = [:]

    func activeJob(for reciterId: UUID) -> DownloadJob? {
        jobs.values.first { $0.reciterId == reciterId && !$0.isDone }
    }

    func recentlyCompletedJob(for reciterId: UUID) -> DownloadJob? {
        jobs.values.first { $0.reciterId == reciterId && $0.isDone }
    }

    // MARK: - Enqueue

    /// Starts downloading `surahs` for `reciter`. Returns the job ID so callers can track progress.
    @discardableResult
    func enqueue(surahs: [Int], reciter: Reciter, context: ModelContext) -> UUID {
        let jobId = UUID()
        guard !surahs.isEmpty, let _ = reciter.id else { return jobId }

        jobs[jobId] = DownloadJob(
            id: jobId,
            reciterId: reciter.id!,
            reciterName: reciter.safeName,
            totalSurahCount: surahs.count
        )

        Task {
            // Ask for extra background execution time
            var bgId: UIBackgroundTaskIdentifier = .invalid
            bgId = UIApplication.shared.beginBackgroundTask(withName: "TilawaDownload-\(jobId)") {
                if bgId != .invalid {
                    UIApplication.shared.endBackgroundTask(bgId)
                }
            }

            let cache = AudioFileCache.shared
            let metadata = QuranMetadataService.shared

            // Up to 4 surahs concurrently. Each surah itself downloads its ayaat in parallel
            // (AudioFileCache.downloadSurah already caps at 6 ayaat concurrently).
            // Note: child tasks capture `reciter` (@Model). Safe in Swift 5 mode since
            // the object is read-only during downloads.
            await withTaskGroup(of: (Int, Bool).self) { group in
                var inFlight = 0
                for surah in surahs {
                    // Throttle to 4 concurrent surah tasks
                    while inFlight >= 4 {
                        if let (done, ok) = await group.next() {
                            inFlight -= 1
                            applyResult(jobId: jobId, surah: done, success: ok)
                        }
                    }
                    let s = surah
                    group.addTask {
                        do {
                            try await cache.downloadSurah(s, reciter: reciter, metadata: metadata) { p in
                                Task { @MainActor [weak self] in
                                    self?.jobs[jobId]?.surahProgress[s] = min(p, 0.99)
                                }
                            }
                            return (s, true)
                        } catch {
                            return (s, false)
                        }
                    }
                    inFlight += 1
                }
                for await (done, ok) in group {
                    applyResult(jobId: jobId, surah: done, success: ok)
                }
            }

            // Refresh reciter's downloadedSurahsJSON to reflect what's actually on disk
            await refreshCachedSurahs(for: reciter, context: context)

            // Fire local notification
            let job = jobs[jobId]
            await sendCompletionNotification(
                reciterName: reciter.safeName,
                completed: job?.completedCount ?? 0,
                failed: job?.failedSurahs.count ?? 0
            )

            if bgId != .invalid {
                UIApplication.shared.endBackgroundTask(bgId)
                bgId = .invalid
            }

            // Keep job visible briefly so the UI can read completion state
            try? await Task.sleep(for: .seconds(4))
            jobs.removeValue(forKey: jobId)
        }

        return jobId
    }

    // MARK: - Notification permission

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Private helpers

    private func applyResult(jobId: UUID, surah: Int, success: Bool) {
        if success {
            jobs[jobId]?.surahProgress[surah] = 1.0
        } else {
            jobs[jobId]?.failedSurahs.insert(surah)
            jobs[jobId]?.surahProgress[surah] = 0
        }
    }

    private func refreshCachedSurahs(for reciter: Reciter, context: ModelContext) async {
        let cache = AudioFileCache.shared
        let metadata = QuranMetadataService.shared
        var cached: [Int] = []
        for surah in 1...114 {
            if await cache.isSurahFullyCached(surah, reciter: reciter, metadata: metadata) {
                cached.append(surah)
            }
        }
        if let data = try? JSONEncoder().encode(cached),
           let json = String(data: data, encoding: .utf8) {
            reciter.downloadedSurahsJSON = json
        }
        reciter.isDownloaded = (cached.count == 114)
        try? context.save()
    }

    private func sendCompletionNotification(reciterName: String, completed: Int, failed: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = failed == 0
            ? "\(completed) surah\(completed == 1 ? "" : "s") downloaded for \(reciterName)."
            : "\(completed) downloaded, \(failed) failed for \(reciterName)."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
