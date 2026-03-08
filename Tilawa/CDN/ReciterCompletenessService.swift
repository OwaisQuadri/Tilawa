import Foundation

/// Per-riwayah coverage report for a reciter's personal recordings.
struct RiwayahCoverage {
    let riwayah: Riwayah
    /// All ayahs touched by any segment (single or multi-ayah).
    let coveredAyahs: Set<AyahRef>
    /// Ayahs covered by single-ayah segments only (upload-ready).
    let uploadReadyAyahs: Set<AyahRef>
    let totalAyahs: Int  // 6236 for Hafs

    var coverageCount: Int { coveredAyahs.count }
    var uploadReadyCount: Int { uploadReadyAyahs.count }
    var missingCount: Int { totalAyahs - coveredAyahs.count }
    /// Multi-ayah segments covering ayahs that lack a single-ayah segment.
    var needsSplittingCount: Int { coveredAyahs.subtracting(uploadReadyAyahs).count }
    var isUploadReady: Bool { uploadReadyCount == totalAyahs }
    var coverageFraction: Double { totalAyahs > 0 ? Double(coverageCount) / Double(totalAyahs) : 0 }
    var uploadReadyFraction: Double { totalAyahs > 0 ? Double(uploadReadyCount) / Double(totalAyahs) : 0 }
}

/// Computes per-riwayah coverage for a reciter's personal recording segments.
enum ReciterCompletenessService {

    /// Returns coverage for the given riwayah from the reciter's segments.
    static func coverage(
        for segments: [RecordingSegment],
        riwayah: Riwayah,
        metadata: QuranMetadataService = .shared
    ) -> RiwayahCoverage {
        let total = metadata.totalAyahCount
        var covered = Set<AyahRef>()
        var uploadReady = Set<AyahRef>()

        for segment in segments {
            guard segment.safeRiwayah == riwayah else { continue }
            let start = segment.primaryAyahRef
            let end = segment.endAyahRef

            if start == end {
                // Single-ayah segment: both covered and upload-ready
                covered.insert(start)
                uploadReady.insert(start)
            } else {
                // Multi-ayah segment: expand range, covered but not upload-ready
                var current: AyahRef? = start
                while let ref = current, ref <= end {
                    covered.insert(ref)
                    current = metadata.ayah(after: ref)
                }
            }
        }

        return RiwayahCoverage(
            riwayah: riwayah,
            coveredAyahs: covered,
            uploadReadyAyahs: uploadReady,
            totalAyahs: total
        )
    }

    /// Returns coverage for all riwayahs present in the segments.
    static func allCoverage(
        for segments: [RecordingSegment],
        metadata: QuranMetadataService = .shared
    ) -> [RiwayahCoverage] {
        let riwayahs = Set(segments.map(\.safeRiwayah))
        return riwayahs.map { coverage(for: segments, riwayah: $0, metadata: metadata) }
            .sorted { $0.coverageCount > $1.coverageCount }
    }
}
