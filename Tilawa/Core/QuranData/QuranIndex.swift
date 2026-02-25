import Foundation

/// A reference to a specific ayah in the Quran.
struct AyahRef: Hashable, Codable, Sendable, Comparable {
    let surah: Int  // 1-114
    let ayah: Int   // 1-based

    static func < (lhs: AyahRef, rhs: AyahRef) -> Bool {
        if lhs.surah != rhs.surah { return lhs.surah < rhs.surah }
        return lhs.ayah < rhs.ayah
    }
}

/// A reference to a specific page in the Mushaf.
struct PageRef: Hashable, Codable, Sendable {
    let page: Int   // 1-604
}

/// A range of ayahs (inclusive).
struct AyahRange: Hashable, Codable, Sendable {
    let start: AyahRef
    let end: AyahRef

    func contains(_ ref: AyahRef) -> Bool {
        ref >= start && ref <= end
    }
}
