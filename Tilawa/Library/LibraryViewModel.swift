import ActivityKit
import Foundation
import SwiftData
import UIKit

/// Drives sheet/picker presentation state for LibraryView.
/// Also orchestrates imports via AudioImporter and auto-adds reciters to the playback priority list.
@Observable
@MainActor
final class LibraryViewModel {

    var isShowingAudioPicker = false
    var isShowingVideoPicker = false
    var isShowingYouTubeImport = false
    var pendingAnnotationRecording: Recording?
    var importError: String?
    var isImporting = false
    var importProgress: (current: Int, total: Int, fileName: String)?
    /// In-progress and failed YouTube imports shown as inline rows in the library.
    var pendingYouTubeImports: [YouTubeImportTask] = []

    private let importer = AudioImporter()
    private var importActivity: Activity<ImportActivityAttributes>?
    /// Active download tasks keyed by YouTubeImportTask.id; used for pause/cancel.
    private var downloadTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Import audio files

    func importAudioFile(urls: [URL], context: ModelContext) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        importError = nil
        let bgTask = beginBackgroundTask()
        startImportActivity(total: urls.count, firstName: urls[0].lastPathComponent)

        var errors: [String] = []
        for (index, url) in urls.enumerated() {
            let name = url.lastPathComponent
            importProgress = (current: index + 1, total: urls.count, fileName: name)
            updateImportActivity(completed: index, total: urls.count, currentFileName: name)
            do {
                let recording = try await importer.importAudioFile(at: url, context: context)
                addToPlaybackPriority(reciter: recording.reciter, context: context, isPersonal: true)
            } catch {
                errors.append("\"\(name)\": \(error.localizedDescription)")
            }
        }

        importProgress = nil
        isImporting = false
        endImportActivity()
        endBackgroundTask(bgTask)
        if !errors.isEmpty { importError = errors.joined(separator: "\n") }
    }

    // MARK: - Import video files

    func importVideoFile(urls: [URL], context: ModelContext) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        importError = nil
        let bgTask = beginBackgroundTask()
        startImportActivity(total: urls.count, firstName: urls[0].lastPathComponent)

        var errors: [String] = []
        for (index, url) in urls.enumerated() {
            let name = url.lastPathComponent
            importProgress = (current: index + 1, total: urls.count, fileName: name)
            updateImportActivity(completed: index, total: urls.count, currentFileName: name)
            do {
                let recording = try await importer.importVideoFile(at: url, context: context)
                addToPlaybackPriority(reciter: recording.reciter, context: context, isPersonal: true)
            } catch {
                errors.append("\"\(name)\": \(error.localizedDescription)")
            }
        }

        importProgress = nil
        isImporting = false
        endImportActivity()
        endBackgroundTask(bgTask)
        if !errors.isEmpty { importError = errors.joined(separator: "\n") }
    }

    // MARK: - Import from YouTube

    func importFromYouTube(urlString: String, context: ModelContext) {
        let task = YouTubeImportTask(urlString: urlString)
        pendingYouTubeImports.append(task)
        startDownload(for: task, context: context)
    }

    func removePendingYouTubeImport(_ task: YouTubeImportTask) {
        downloadTasks[task.id]?.cancel()
        downloadTasks[task.id] = nil
        pendingYouTubeImports.removeAll { $0.id == task.id }
    }

    private func startDownload(for task: YouTubeImportTask, context: ModelContext) {
        let taskID = task.id
        let urlString = task.urlString

        let downloadTask = Task {
            do {
                let (tempURL, videoID, title) = try await YouTubeAudioImporter().downloadAudio(
                    from: urlString,
                    onTitle: { fetchedTitle in
                        Task { @MainActor [weak self] in
                            self?.pendingYouTubeImports
                                .first(where: { $0.id == taskID })?
                                .title = fetchedTitle
                        }
                    },
                    onProgress: { progress in
                        Task { @MainActor [weak self] in
                            guard let task = self?.pendingYouTubeImports
                                .first(where: { $0.id == taskID }),
                                  case .downloading = task.state else { return }
                            task.state = .downloading(progress: progress)
                        }
                    }
                )
                let recordingTitle = title
                    ?? pendingYouTubeImports.first(where: { $0.id == taskID })?.title
                    ?? videoID
                let recording = try await importer.importDownloadedFile(
                    at: tempURL, title: recordingTitle, context: context)
                addToPlaybackPriority(reciter: recording.reciter, context: context, isPersonal: true)
                downloadTasks[taskID] = nil
                pendingYouTubeImports.removeAll { $0.id == taskID }
            } catch is CancellationError {
                // User stopped — removePendingYouTubeImport already cleaned up the row.
                downloadTasks[taskID] = nil
            } catch {
                downloadTasks[taskID] = nil
                pendingYouTubeImports
                    .first(where: { $0.id == taskID })?
                    .state = .failed(error.localizedDescription)
            }
        }
        downloadTasks[taskID] = downloadTask
    }

    // MARK: - Priority list management

    /// Adds a reciter to PlaybackSettings.reciterPriority and all segment overrides if not already present.
    /// Personal reciters are inserted at order 0 (top) of the global list; CDN reciters appended at end.
    func addToPlaybackPriority(reciter: Reciter?, context: ModelContext, isPersonal: Bool) {
        guard let reciter, let reciterId = reciter.id else { return }

        let settingsDescriptor = FetchDescriptor<PlaybackSettings>()
        guard let settings = try? context.fetch(settingsDescriptor).first else { return }

        // Global priority
        let alreadyInList = (settings.reciterPriority ?? [])
            .contains { $0.reciterId == reciterId }
        if !alreadyInList {
            let newOrder: Int
            if isPersonal {
                // Shift all existing entries down to make room at slot 0
                for entry in settings.reciterPriority ?? [] {
                    entry.order = (entry.order ?? 0) + 1
                }
                newOrder = 0
            } else {
                newOrder = ((settings.reciterPriority ?? []).compactMap { $0.order }.max() ?? -1) + 1
            }
            let entry = ReciterPriorityEntry(order: newOrder, reciterId: reciterId)
            context.insert(entry)
            settings.reciterPriority = (settings.reciterPriority ?? []) + [entry]
        }

        // Segment overrides — sync reciter into each override that doesn't already have it
        for segment in settings.segmentOverrides ?? [] {
            let alreadyInSegment = (segment.reciterPriority ?? [])
                .contains { $0.reciterId == reciterId }
            guard !alreadyInSegment else { continue }
            let maxOrder = (segment.reciterPriority ?? []).compactMap { $0.order }.max() ?? -1
            let segEntry = SegmentReciterEntry(order: maxOrder + 1, reciterId: reciterId)
            context.insert(segEntry)
            segment.reciterPriority = (segment.reciterPriority ?? []) + [segEntry]
        }

        try? context.save()
    }

    // MARK: - Background task helpers

    private func beginBackgroundTask() -> UIBackgroundTaskIdentifier {
        var bgId: UIBackgroundTaskIdentifier = .invalid
        bgId = UIApplication.shared.beginBackgroundTask(withName: "TilawaImport") {
            UIApplication.shared.endBackgroundTask(bgId)
        }
        return bgId
    }

    private func endBackgroundTask(_ id: UIBackgroundTaskIdentifier) {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
    }

    // MARK: - Live Activity helpers

    private func startImportActivity(total: Int, firstName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let initial = ImportActivityAttributes.ContentState(
            filesCompleted: 0, filesTotal: total, currentFileName: firstName)
        let content = ActivityContent(state: initial, staleDate: nil)
        importActivity = try? Activity.request(
            attributes: ImportActivityAttributes(), content: content, pushType: nil)
    }

    private func updateImportActivity(completed: Int, total: Int, currentFileName: String) {
        guard let activity = importActivity else { return }
        let state = ImportActivityAttributes.ContentState(
            filesCompleted: completed, filesTotal: total, currentFileName: currentFileName)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func endImportActivity() {
        guard let activity = importActivity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        importActivity = nil
    }
}
