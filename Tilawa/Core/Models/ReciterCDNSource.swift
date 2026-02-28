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
    }

    // MARK: - Computed
    var safeRiwayah: Riwayah { Riwayah(rawValue: riwayah ?? "") ?? .hafs }

    var namingPattern: ReciterNamingPattern {
        if urlTemplate != nil { return .urlTemplate }
        return ReciterNamingPattern(rawValue: namingPatternType ?? "") ?? .surahAyah
    }
}
