import SwiftData
import Foundation

@Model
final class Reciter {
    var id: UUID?
    var name: String?
    var shortName: String?
    var riwayah: String?             // Riwayah.rawValue — required, user-specified
    var remoteBaseURL: String?       // e.g. "https://everyayah.com/data/Minshawi_Murattal_128kbps/"
    var localCacheDirectory: String? // relative path in app Caches dir (defaults to id.uuidString)
    var audioFileFormat: String?     // "mp3" | "opus" | "m4a"
    /// Naming pattern for CDN audio files.
    /// "surah_ayah" → {surah3}{ayah3}.{format} (e.g. 001001.mp3)
    /// "sequential" → {1..6236}.{format}        (e.g. 1.mp3)
    var namingPatternType: String?
    var isDownloaded: Bool?
    var downloadedSurahsJSON: String? // JSON [Int] of fully-downloaded surah numbers
    var coverImageURL: String?
    var sortOrder: Int?
    var style: String?               // "murattal" | "mujawwad" | "muallim" (optional display only)
    /// Full URL template used when namingPatternType == "url_template".
    /// Tokens: ${s}/${ss}/${sss} (surah), ${a}/${aa}/${aaa} (ayah).
    var audioURLTemplate: String?
    /// Priority position of the CDN manifest source (remoteBaseURL) in the unified source list.
    /// nil = ordered after all explicitly-positioned items.
    var cdnManifestOrder: Int?
    /// Priority position of the CDN url-template source (audioURLTemplate) in the unified source list.
    /// nil = ordered after all explicitly-positioned items.
    var cdnTemplateOrder: Int?
    /// JSON-encoded [AyahRef] of ayahs confirmed absent on the CDN.
    /// nil  = availability check not yet performed (treat all ayahs as available).
    /// "[]" = check performed; reciter is fully complete.
    var missingAyahsJSON: String?

    @Relationship(deleteRule: .cascade)
    var recordings: [Recording]?

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.name = nil; self.shortName = nil
        self.riwayah = nil
        self.remoteBaseURL = nil; self.localCacheDirectory = nil
        self.audioFileFormat = nil; self.namingPatternType = nil
        self.isDownloaded = nil; self.downloadedSurahsJSON = nil
        self.coverImageURL = nil; self.sortOrder = nil; self.style = nil
        self.audioURLTemplate = nil
        self.cdnManifestOrder = nil
        self.cdnTemplateOrder = nil
        self.missingAyahsJSON = nil
        self.recordings = nil
    }

    // MARK: - Convenience initializer (from a manifest)
    convenience init(name: String, riwayah: Riwayah) {
        self.init()
        self.id = UUID()
        self.name = name
        self.riwayah = riwayah.rawValue
        self.isDownloaded = false
        self.audioFileFormat = "mp3"
        self.namingPatternType = ReciterNamingPattern.surahAyah.rawValue
    }

    // MARK: - Safe computed properties
    var safeName: String { name ?? "Unknown Reciter" }
    var safeRiwayah: Riwayah { Riwayah(rawValue: riwayah ?? "") ?? .hafs }
    var namingPattern: ReciterNamingPattern {
        ReciterNamingPattern(rawValue: namingPatternType ?? "") ?? .surahAyah
    }
    var hasCDN: Bool { remoteBaseURL != nil || audioURLTemplate != nil }
    var hasPersonalRecordings: Bool { !(recordings ?? []).isEmpty }

    var downloadedSurahs: [Int] {
        guard let json = downloadedSurahsJSON,
              let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
        return list
    }

    /// True once the CDN availability check has been performed for this reciter.
    var availabilityChecked: Bool { missingAyahsJSON != nil }

    /// Ayahs confirmed absent on the CDN. Empty when check not yet done or reciter is complete.
    var missingAyahs: [AyahRef] {
        guard let json = missingAyahsJSON,
              let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([AyahRef].self, from: data) else { return [] }
        return list
    }
}
