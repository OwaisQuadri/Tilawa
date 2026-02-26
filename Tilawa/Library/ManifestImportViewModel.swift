import Foundation
import SwiftData

enum ReciterImportMode: String, CaseIterable {
    case jsonURL   = "JSON URL"
    case jsonFile  = "JSON File"
    case urlFormat = "URL Format"
}

@Observable
@MainActor
final class ManifestImportViewModel {

    var importMode: ReciterImportMode = .jsonURL

    // MARK: - JSON URL mode
    var manifestURL: String = ""

    // MARK: - JSON File mode
    var selectedJSONFileURL: URL?
    var selectedJSONFileName: String?
    var isShowingJSONFilePicker = false

    // MARK: - URL Format mode
    var urlFormatName: String = ""
    var urlFormatRiwayah: Riwayah = .hafs
    var urlFormatStyle: String = "murattal"
    var urlFormatTemplate: String = ""

    // MARK: - Shared state
    var isLoading = false
    var errorMessage: String?
    var importedReciter: Reciter?

    // MARK: - URL Format helpers

    /// Live preview of the substituted URL using Al-Fatiha 1:1 as example.
    var urlFormatPreview: String {
        guard !urlFormatTemplate.isEmpty else { return "" }
        return AudioFileCache.substituteURLTemplate(urlFormatTemplate, surah: 1, ayah: 1)
    }

    /// File extension inferred from the template URL (e.g. "mp3" from "…001001.mp3").
    var inferredFormat: String {
        let ext = (urlFormatTemplate as NSString).pathExtension.lowercased()
        let supported = ["mp3", "m4a", "opus", "wav"]
        return supported.contains(ext) ? ext : "mp3"
    }

    // MARK: - Import: JSON URL

    func importFromURL(context: ModelContext) async {
        guard let url = URL(string: manifestURL.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https" else {
            errorMessage = "Please enter a valid HTTPS URL."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw ReciterImportError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            importedReciter = try importManifestData(data, context: context)
        } catch let e as ManifestImportError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Import: JSON File

    func pickJSONFile(url: URL) {
        selectedJSONFileURL = url
        selectedJSONFileName = url.lastPathComponent
    }

    func importFromFile(context: ModelContext) {
        guard let fileURL = selectedJSONFileURL else {
            errorMessage = "No file selected."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let reciter = try ReciterManifestImporter().importManifest(from: fileURL, context: context)
            try context.save()
            fileURL.stopAccessingSecurityScopedResource()
            importedReciter = reciter
        } catch let e as ManifestImportError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Import: URL Format

    func importFromURLFormat(context: ModelContext) {
        let name     = urlFormatName.trimmingCharacters(in: .whitespaces)
        let template = urlFormatTemplate.trimmingCharacters(in: .whitespaces)

        guard !name.isEmpty else { errorMessage = "Reciter name is required."; return }
        guard !template.isEmpty else { errorMessage = "URL template is required."; return }

        let hasSurahToken = template.contains("${s")
        let hasAyahToken  = template.contains("${a")
        guard hasSurahToken && hasAyahToken else {
            errorMessage = "Template must include a surah token (${s}, ${ss}, ${sss}) and an ayah token (${a}, ${aa}, ${aaa})."
            return
        }
        let preview = AudioFileCache.substituteURLTemplate(template, surah: 1, ayah: 1)
        guard URL(string: preview)?.scheme == "https" else {
            errorMessage = "Template must produce a valid HTTPS URL.\nPreview: \(preview)"
            return
        }

        isLoading = true
        errorMessage = nil

        let riwayah = urlFormatRiwayah.rawValue
        let format  = inferredFormat

        do {
            let descriptor = FetchDescriptor<Reciter>(
                predicate: #Predicate { $0.name == name && $0.riwayah == riwayah }
            )
            let existing = try context.fetch(descriptor)
            let reciter  = existing.first ?? Reciter()
            if existing.isEmpty { context.insert(reciter) }

            reciter.id               = reciter.id ?? UUID()
            reciter.name             = name
            reciter.riwayah          = riwayah
            reciter.style            = urlFormatStyle
            reciter.audioFileFormat  = format
            reciter.namingPatternType = ReciterNamingPattern.urlTemplate.rawValue
            reciter.audioURLTemplate = template
            reciter.localCacheDirectory = reciter.id!.uuidString
            reciter.isDownloaded     = false

            try context.save()
            importedReciter = reciter
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Priority list

    func addReciterToPriorityList(_ reciter: Reciter, context: ModelContext) {
        guard let reciterId = reciter.id else { return }
        let descriptor = FetchDescriptor<PlaybackSettings>()
        guard let settings = try? context.fetch(descriptor).first else { return }

        let alreadyInList = (settings.reciterPriority ?? [])
            .contains { $0.reciterId == reciterId }
        guard !alreadyInList else { return }

        let maxOrder = (settings.reciterPriority ?? []).compactMap { $0.order }.max() ?? -1
        let entry = ReciterPriorityEntry(order: maxOrder + 1, reciterId: reciterId)
        context.insert(entry)
        settings.reciterPriority = (settings.reciterPriority ?? []) + [entry]
        try? context.save()
    }

    // MARK: - Helpers

    private func importManifestData(_ data: Data, context: ModelContext) throws -> Reciter {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let reciter = try ReciterManifestImporter().importManifest(from: tempURL, context: context)
        try context.save()
        return reciter
    }
}

private enum ReciterImportError: LocalizedError {
    case httpError(Int)
    var errorDescription: String? {
        if case .httpError(let code) = self {
            return "Server returned HTTP \(code). Check the URL and try again."
        }
        return nil
    }
}
