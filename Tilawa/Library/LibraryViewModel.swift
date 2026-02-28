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
    var pendingAnnotationRecording: Recording?
    var importError: String?
    var isImporting = false
    var importProgress: (current: Int, total: Int, fileName: String)?

    private let importer = AudioImporter()
    private var importActivity: Activity<ImportActivityAttributes>?

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

    // MARK: - Priority list management

    /// Adds a reciter to PlaybackSettings.reciterPriority if not already present.
    /// Personal reciters are inserted at order 0 (top); CDN reciters appended at end.
    func addToPlaybackPriority(reciter: Reciter?, context: ModelContext, isPersonal: Bool) {
        guard let reciter, let reciterId = reciter.id else { return }

        let settingsDescriptor = FetchDescriptor<PlaybackSettings>()
        guard let settings = try? context.fetch(settingsDescriptor).first else { return }

        let alreadyInList = (settings.reciterPriority ?? [])
            .contains { $0.reciterId == reciterId }
        guard !alreadyInList else { return }

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
