import SwiftData
import Foundation

/// Represents a single CDN audio source for a reciter.
/// One reciter can have multiple CDN sources (e.g. different riwayaat from different CDNs).
@Model
final class ReciterCDNSource {

    var id: UUID?
    var reciter: Reciter?

    /// Base URL for manifest-style CDN (e.g. "https://everyayah.com/data/Minshawy_Murattal_128kbps/")
    var baseURL: String?
    /// Full URL template for template-style CDN (with ${s}/${a} tokens).
    /// When set, baseURL is unused.
    var urlTemplate: String?

    var riwayah: String?           // Riwayah.rawValue
    var audioFileFormat: String?   // "mp3" | "m4a" | "opus" | "wav"
    var namingPatternType: String? // ReciterNamingPattern.rawValue
    var sortOrder: Int?

    /// Stable folder identifier on the CDN (e.g. "yasser-ad-dosari-hafs-875a6a").
    /// Used to ensure re-uploads overwrite the same R2 path.
    var cdnFolderId: String?

    /// CDN version number, incremented on each upload. Used to detect content changes.
    var cdnVersion: Int?

    /// JSON-encoded [AyahRef] of ayahs confirmed absent on this CDN source.
    /// nil  = availability check not yet performed.
    /// "[]" = check performed; source is fully complete.
    var missingAyahsJSON: String?

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.reciter = nil
        self.baseURL = nil
        self.urlTemplate = nil
        self.riwayah = nil
        self.audioFileFormat = nil
        self.namingPatternType = nil
        self.sortOrder = nil
        self.cdnFolderId = nil
        self.cdnVersion = nil
        self.missingAyahsJSON = nil
    }

    // MARK: - Computed
    var safeRiwayah: Riwayah { Riwayah(rawValue: riwayah ?? "") ?? .hafs }

    var namingPattern: ReciterNamingPattern {
        if urlTemplate != nil { return .urlTemplate }
        return ReciterNamingPattern(rawValue: namingPatternType ?? "") ?? .surahAyah
    }

    var availabilityChecked: Bool { missingAyahsJSON != nil }

    var missingAyahs: [AyahRef] {
        guard let json = missingAyahsJSON,
              let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([AyahRef].self, from: data) else { return [] }
        return list
    }
}
