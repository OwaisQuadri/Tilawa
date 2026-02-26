import Foundation
import SwiftData

/// Drives sheet/picker presentation state for LibraryView.
/// Also orchestrates imports via AudioImporter and auto-adds reciters to the playback priority list.
@Observable
@MainActor
final class LibraryViewModel {

    var isShowingAudioPicker = false
    var isShowingVideoPicker = false
    var isShowingManifestSheet = false
    var pendingAnnotationRecording: Recording?
    var importError: String?
    var isImporting = false

    private let importer = AudioImporter()

    // MARK: - Import audio file

    func importAudioFile(urls: [URL], context: ModelContext) async {
        guard let url = urls.first else { return }
        isImporting = true
        importError = nil
        do {
            let recording = try await importer.importAudioFile(at: url, context: context)
            addToPlaybackPriority(reciter: recording.reciter, context: context,
                                  isPersonal: true)
        } catch {
            importError = error.localizedDescription
        }
        isImporting = false
    }

    // MARK: - Import video file

    func importVideoFile(urls: [URL], context: ModelContext) async {
        guard let url = urls.first else { return }
        isImporting = true
        importError = nil
        do {
            let recording = try await importer.importVideoFile(at: url, context: context)
            addToPlaybackPriority(reciter: recording.reciter, context: context,
                                  isPersonal: true)
        } catch {
            importError = error.localizedDescription
        }
        isImporting = false
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
}
