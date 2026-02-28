import SwiftData
import Foundation

@Model
final class Reciter {
    var id: UUID?
    var name: String?
    var shortName: String?
    var localCacheDirectory: String? // relative path in app Caches dir (defaults to id.uuidString)
    var isDownloaded: Bool?
    var downloadedSurahsJSON: String? // JSON [Int] of fully-downloaded surah numbers
    var coverImageURL: String?
    var sortOrder: Int?
    var style: String?               // "murattal" | "mujawwad" | "muallim" (optional display only)
    /// JSON-encoded [AyahRef] of ayahs confirmed absent on the CDN.
    /// nil  = availability check not yet performed (treat all ayahs as available).
    /// "[]" = check performed; reciter is fully complete.
    var missingAyahsJSON: String?

    @Relationship(deleteRule: .cascade)
    var cdnSources: [ReciterCDNSource]?

    @Relationship(deleteRule: .cascade)
    var recordings: [Recording]?

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.name = nil; self.shortName = nil
        self.localCacheDirectory = nil
        self.isDownloaded = nil; self.downloadedSurahsJSON = nil
        self.coverImageURL = nil; self.sortOrder = nil; self.style = nil
        self.missingAyahsJSON = nil
        self.cdnSources = nil
        self.recordings = nil
    }

    // MARK: - Safe computed properties
    var safeName: String { name ?? "Unknown Reciter" }
    var hasCDN: Bool { !(cdnSources ?? []).isEmpty }
    var hasPersonalRecordings: Bool { !(recordings ?? []).isEmpty }

    /// All riwayaat this reciter covers, sorted by segment count descending.
    /// CDN source riwayaat are included (with segmentCount = 0 if no personal segments match).
    /// Personal-recording riwayaat derive from segments.
    var riwayahSummary: [(riwayah: Riwayah, segmentCount: Int)] {
        var counts: [Riwayah: Int] = [:]
        for recording in recordings ?? [] {
            for segment in recording.segments ?? [] {
                counts[segment.safeRiwayah, default: 0] += 1
            }
        }
        for source in cdnSources ?? [] {
            if let raw = source.riwayah, let r = Riwayah(rawValue: raw) {
                counts[r] = counts[r] ?? 0
            }
        }
        return counts
            .map { (riwayah: $0.key, segmentCount: $0.value) }
            .sorted { $0.segmentCount > $1.segmentCount }
    }

    /// The riwayah with the most segments, or .hafs as last-resort fallback.
    var dominantRiwayah: Riwayah { riwayahSummary.first?.riwayah ?? .hafs }

    /// Short display label: dominant riwayah name, with "+N" suffix when multiple riwayaat exist.
    /// e.g. "Hafs" or "Hafs +2". Returns "—" if no riwayah info is available.
    var riwayahSummaryLabel: String {
        let summary = riwayahSummary
        guard !summary.isEmpty else { return "—" }
        let dominant = summary[0].riwayah.displayName
        return summary.count > 1 ? "\(dominant) +\(summary.count - 1)" : dominant
    }

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
