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
    var importedSource: ReciterCDNSource?

    // MARK: - URL Format helpers

    var urlFormatPreview: String {
        guard !urlFormatTemplate.isEmpty else { return "" }
        return AudioFileCache.substituteURLTemplate(urlFormatTemplate, surah: 1, ayah: 1)
    }

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
            let reciter = try importManifestData(data, context: context)
            importedReciter = reciter
            importedSource = reciter.cdnSources?.first
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
            importedSource = reciter.cdnSources?.first
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
            // Find or create reciter by name
            let descriptor = FetchDescriptor<Reciter>(predicate: #Predicate { $0.name == name })
            let existing = try context.fetch(descriptor)
            let reciter  = existing.first ?? Reciter()
            if existing.isEmpty { context.insert(reciter) }

            reciter.id   = reciter.id ?? UUID()
            reciter.name = name
            reciter.style = urlFormatStyle
            reciter.localCacheDirectory = reciter.localCacheDirectory ?? reciter.id!.uuidString
            reciter.isDownloaded = false

            // Find or create CDN source for this template
            let existingSource = (reciter.cdnSources ?? []).first { $0.urlTemplate == template }
            let source = existingSource ?? ReciterCDNSource()
            if existingSource == nil {
                source.id = UUID()
                source.reciter = reciter
                context.insert(source)
                reciter.cdnSources = (reciter.cdnSources ?? []) + [source]
            }

            source.urlTemplate = template
            source.riwayah = riwayah
            source.audioFileFormat = format
            source.namingPatternType = ReciterNamingPattern.urlTemplate.rawValue

            try context.save()
            importedReciter = reciter
            importedSource = source
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
            let source: ReciterCDNSource?

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
                source = reciter.cdnSources?.first { $0.baseURL == baseURL }

            case .urlTemplate(let template, let format):
                let name = preset.name
                let descriptor = FetchDescriptor<Reciter>(predicate: #Predicate { $0.name == name })
                let existing = try context.fetch(descriptor)
                let r = existing.first ?? Reciter()
                if existing.isEmpty { context.insert(r) }

                r.id = r.id ?? UUID()
                r.name = preset.name
                r.shortName = preset.shortName
                r.style = preset.style
                r.localCacheDirectory = r.localCacheDirectory ?? r.id!.uuidString
                r.isDownloaded = false

                let existingSource = (r.cdnSources ?? []).first { $0.urlTemplate == template }
                let src = existingSource ?? ReciterCDNSource()
                if existingSource == nil {
                    src.id = UUID()
                    src.reciter = r
                    context.insert(src)
                    r.cdnSources = (r.cdnSources ?? []) + [src]
                }

                src.urlTemplate = template
                src.riwayah = preset.riwayah.rawValue
                src.audioFileFormat = format
                src.namingPatternType = ReciterNamingPattern.urlTemplate.rawValue

                reciter = r
                source = src
            }

            try context.save()
            importedReciter = reciter
            importedSource = source
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

        let alreadyInGlobal = (settings.reciterPriority ?? [])
            .contains { $0.reciterId == reciterId }
        if !alreadyInGlobal {
            let maxOrder = (settings.reciterPriority ?? []).compactMap { $0.order }.max() ?? -1
            let entry = ReciterPriorityEntry(order: maxOrder + 1, reciterId: reciterId)
            context.insert(entry)
            settings.reciterPriority = (settings.reciterPriority ?? []) + [entry]
        }

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
