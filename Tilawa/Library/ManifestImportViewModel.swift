import Foundation
import SwiftData

enum ReciterImportMode: String, CaseIterable {
    case presets   = "Presets"
    case jsonURL   = "URL"
    case jsonFile  = "File"
    case urlFormat = "Template"
}

@Observable
@MainActor
final class ManifestImportViewModel {

    var importMode: ReciterImportMode = .presets

    // MARK: - Presets mode
    var selectedPreset: ReciterPreset? = nil

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

    // MARK: - Import: Preset

    func importFromPreset(_ preset: ReciterPreset, context: ModelContext) {
        isLoading = true
        errorMessage = nil
        do {
            let reciter: Reciter
            switch preset.source {
            case .manifestBaseURL(let baseURL, let namingPattern, let format, _):
                let manifest = ReciterManifest(
                    schemaVersion: "1.0",
                    reciter: ReciterManifest.ReciterInfo(
                        name: preset.name,
                        shortName: preset.shortName,
                        riwayah: preset.riwayah.rawValue,
                        style: preset.style
                    ),
                    audio: ReciterManifest.AudioInfo(
                        baseUrl: baseURL,
                        format: format,
                        namingPattern: namingPattern.rawValue,
                        bitrate: nil
                    )
                )
                reciter = try ReciterManifestImporter().createReciter(from: manifest, context: context)

            case .urlTemplate(let template, let format):
                let name    = preset.name
                let riwayah = preset.riwayah.rawValue
                let descriptor = FetchDescriptor<Reciter>(
                    predicate: #Predicate { $0.name == name && $0.riwayah == riwayah }
                )
                let existing = try context.fetch(descriptor)
                let r = existing.first ?? Reciter()
                if existing.isEmpty { context.insert(r) }
                r.id                  = r.id ?? UUID()
                r.name                = preset.name
                r.shortName           = preset.shortName
                r.riwayah             = preset.riwayah.rawValue
                r.style               = preset.style
                r.audioFileFormat     = format
                r.namingPatternType   = ReciterNamingPattern.urlTemplate.rawValue
                r.audioURLTemplate    = template
                r.localCacheDirectory = r.id!.uuidString
                r.isDownloaded        = false
                reciter = r
            }

            try context.save()
            importedReciter = reciter
        } catch let e as ManifestImportError {
            errorMessage = e.errorDescription
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

        // Global priority: append at the bottom
        let alreadyInGlobal = (settings.reciterPriority ?? [])
            .contains { $0.reciterId == reciterId }
        if !alreadyInGlobal {
            let maxOrder = (settings.reciterPriority ?? []).compactMap { $0.order }.max() ?? -1
            let entry = ReciterPriorityEntry(order: maxOrder + 1, reciterId: reciterId)
            context.insert(entry)
            settings.reciterPriority = (settings.reciterPriority ?? []) + [entry]
        }

        // Segment overrides: append at the bottom of each segment's priority list
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
