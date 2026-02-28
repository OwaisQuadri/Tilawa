import Foundation
import SwiftData

// MARK: - Manifest schema (user-uploadable JSON)

struct ReciterManifest: Codable {
    let schemaVersion: String
    let reciter: ReciterInfo
    let audio: AudioInfo

    struct ReciterInfo: Codable {
        let name: String
        let shortName: String?
        /// Required. Must be a valid Riwayah rawValue (e.g. "hafs", "warsh").
        let riwayah: String
        let style: String?
    }

    struct AudioInfo: Codable {
        /// Trailing slash required. e.g. "https://everyayah.com/data/Minshawy_Murattal_128kbps/"
        let baseUrl: String
        /// "mp3" | "m4a" | "opus" | "wav"
        let format: String
        /// "surah_ayah" (default) or "sequential"
        let namingPattern: String
        let bitrate: Int?
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case reciter, audio
    }
}

extension ReciterManifest.AudioInfo {
    enum CodingKeys: String, CodingKey {
        case baseUrl = "base_url"
        case format
        case namingPattern = "naming_pattern"
        case bitrate
    }
}

extension ReciterManifest.ReciterInfo {
    enum CodingKeys: String, CodingKey {
        case name
        case shortName = "short_name"
        case riwayah, style
    }
}

// MARK: - Import errors

enum ManifestImportError: LocalizedError {
    case unsupportedSchemaVersion(String)
    case unknownRiwayah(String)
    case invalidBaseURL(String)
    case unknownNamingPattern(String)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let v):
            return "Unsupported schema version '\(v)'. Expected '1.0'."
        case .unknownRiwayah(let r):
            let valid = Riwayah.allCases.map(\.rawValue).joined(separator: ", ")
            return "Unknown riwayah '\(r)'. Must be one of: \(valid)."
        case .invalidBaseURL(let u):
            return "Invalid base URL '\(u)'. Must be a valid HTTPS URL."
        case .unknownNamingPattern(let p):
            return "Unknown naming_pattern '\(p)'. Must be 'surah_ayah' or 'sequential'."
        case .unsupportedFormat(let f):
            return "Unsupported audio format '\(f)'. Must be mp3, m4a, opus, or wav."
        }
    }
}

// MARK: - Importer

final class ReciterManifestImporter {

    private static let supportedFormats = ["mp3", "m4a", "opus", "wav"]

    /// Parses and validates a ReciterManifest.json file, then creates or updates
    /// a `Reciter` @Model and its associated `ReciterCDNSource` in the given ModelContext.
    ///
    /// - Returns: The created or updated `Reciter`.
    /// - Throws: `ManifestImportError` for validation failures, or decoding errors.
    @discardableResult
    func importManifest(from url: URL, context: ModelContext) throws -> Reciter {
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(ReciterManifest.self, from: data)
        return try createReciter(from: manifest, context: context)
    }

    /// Creates a Reciter (and its CDN source) from an already-decoded manifest.
    @discardableResult
    func createReciter(from manifest: ReciterManifest, context: ModelContext) throws -> Reciter {
        guard manifest.schemaVersion == "1.0" else {
            throw ManifestImportError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        guard Riwayah(rawValue: manifest.reciter.riwayah) != nil else {
            throw ManifestImportError.unknownRiwayah(manifest.reciter.riwayah)
        }
        guard let baseURL = URL(string: manifest.audio.baseUrl), baseURL.scheme == "https" else {
            throw ManifestImportError.invalidBaseURL(manifest.audio.baseUrl)
        }
        _ = baseURL
        guard ReciterNamingPattern(rawValue: manifest.audio.namingPattern) != nil else {
            throw ManifestImportError.unknownNamingPattern(manifest.audio.namingPattern)
        }
        guard Self.supportedFormats.contains(manifest.audio.format.lowercased()) else {
            throw ManifestImportError.unsupportedFormat(manifest.audio.format)
        }

        // Find or create reciter by name
        let name = manifest.reciter.name
        let descriptor = FetchDescriptor<Reciter>(predicate: #Predicate { $0.name == name })
        let existingReciters = try context.fetch(descriptor)

        let reciter = existingReciters.first ?? Reciter()
        if existingReciters.isEmpty { context.insert(reciter) }

        reciter.id = reciter.id ?? UUID()
        reciter.name = manifest.reciter.name
        reciter.shortName = manifest.reciter.shortName
        reciter.style = manifest.reciter.style
        reciter.localCacheDirectory = reciter.localCacheDirectory ?? reciter.id!.uuidString
        reciter.isDownloaded = false

        // Find or create CDN source for this baseURL
        let baseUrl = manifest.audio.baseUrl
        let existingSource = (reciter.cdnSources ?? []).first { $0.baseURL == baseUrl }
        let source = existingSource ?? ReciterCDNSource()
        if existingSource == nil {
            source.id = UUID()
            source.reciter = reciter
            context.insert(source)
            reciter.cdnSources = (reciter.cdnSources ?? []) + [source]
        }

        source.baseURL = manifest.audio.baseUrl
        source.riwayah = manifest.reciter.riwayah
        source.audioFileFormat = manifest.audio.format.lowercased()
        source.namingPatternType = manifest.audio.namingPattern

        return reciter
    }
}
