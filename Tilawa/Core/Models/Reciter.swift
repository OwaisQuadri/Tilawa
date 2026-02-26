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
    var hasCDN: Bool { remoteBaseURL != nil }
    var hasPersonalRecordings: Bool { !(recordings ?? []).isEmpty }

    var downloadedSurahs: [Int] {
        guard let json = downloadedSurahsJSON,
              let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
        return list
    }
}
