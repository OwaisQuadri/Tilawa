import Foundation

struct JuzInfo {
    let juz: Int             // 1–30
    let hizb: Int            // 1–60
    let thumun: Int          // 1–240 (global index)
    let thumunInHizb: Int    // 1–4
    let isOnJuzBoundary: Bool
    let isOnHizbBoundary: Bool
    let isOnThumunBoundary: Bool
}

/// Provides Juz, Hizb, and Thumun info for any Mushaf page.
///
/// Thumun (rub' al-hizb) start pages are hardcoded from the Quran Foundation API
/// for the 604-page Al-Madinah Mushaf. Hizb and Juz are derived:
///   hizb i  = thumun (i−1)×4 + 1  → hizbStartPages[i] = thumunStartPages[i×4]
///   juz  i  = thumun (i−1)×8 + 1  → juzStartPages[i]  = thumunStartPages[i×8]
final class JuzService: Sendable {
    static let shared = JuzService()

    // MARK: - Hardcoded Thumun (Rub' al-Hizb) Pages

    /// Start page of each rub el hizb / thumun (index 0 = thumun 1, 240 total).
    /// Sourced from Quran Foundation API for the 604-page Madani mushaf.
    static let thumunStartPages: [Int] = [
          1,   5,   7,   9,  11,  14,  17,  19,  22,  24,
         27,  29,  32,  34,  37,  39,  42,  44,  46,  49,
         51,  54,  56,  59,  62,  64,  67,  69,  72,  74,
         77,  79,  82,  84,  87,  89,  92,  94,  97, 100,
        102, 104, 106, 109, 112, 114, 117, 119, 121, 124,
        126, 129, 132, 134, 137, 140, 142, 144, 146, 148,
        151, 154, 156, 158, 162, 164, 167, 170, 173, 175,
        177, 179, 182, 184, 187, 189, 192, 194, 196, 199,
        201, 204, 206, 209, 212, 214, 217, 219, 222, 224,
        226, 228, 231, 233, 236, 238, 242, 244, 247, 249,
        252, 254, 256, 259, 262, 264, 267, 270, 272, 275,
        277, 280, 282, 284, 287, 289, 292, 295, 297, 299,
        302, 304, 306, 309, 312, 315, 317, 319, 322, 324,
        326, 329, 332, 334, 336, 339, 342, 344, 347, 350,
        352, 354, 356, 359, 362, 364, 367, 369, 371, 374,
        377, 379, 382, 384, 386, 389, 392, 394, 396, 399,
        402, 404, 407, 410, 413, 415, 418, 420, 422, 425,
        426, 429, 431, 433, 436, 439, 442, 444, 446, 449,
        451, 454, 456, 459, 462, 464, 467, 469, 472, 474,
        477, 479, 482, 484, 486, 488, 491, 493, 496, 499,
        502, 505, 507, 510, 513, 515, 517, 519, 522, 524,
        526, 529, 531, 534, 536, 539, 542, 544, 547, 550,
        553, 554, 558, 560, 562, 564, 566, 569, 572, 575,
        577, 579, 582, 585, 587, 589, 591, 594, 596, 599,
    ]

    // MARK: - Derived Division Pages

    /// Start page of each hizb (60 total). Derived: hizbStartPages[i] = thumunStartPages[i×4].
    static let hizbStartPages: [Int] = stride(from: 0, to: thumunStartPages.count, by: 4)
        .map { thumunStartPages[$0] }

    /// Start page of each juz (30 total). Derived: juzStartPages[i] = thumunStartPages[i×8].
    static let juzStartPages: [Int] = stride(from: 0, to: thumunStartPages.count, by: 8)
        .map { thumunStartPages[$0] }

    // MARK: - Public API

    func juzInfo(forPage page: Int) -> JuzInfo {
        let thumunR = Self.rank(of: page, in: Self.thumunStartPages)
        let hizbR   = Self.rank(of: page, in: Self.hizbStartPages)
        let juzR    = Self.rank(of: page, in: Self.juzStartPages)

        return JuzInfo(
            juz:               juzR.index + 1,
            hizb:              hizbR.index + 1,
            thumun:            thumunR.index + 1,
            thumunInHizb:      (thumunR.index % 4) + 1,
            isOnJuzBoundary:   juzR.onBoundary,
            isOnHizbBoundary:  hizbR.onBoundary,
            isOnThumunBoundary: thumunR.onBoundary
        )
    }

    /// Returns the Juz number (1–30) for a given page.
    func juz(forPage page: Int) -> Int {
        Self.rank(of: page, in: Self.juzStartPages).index + 1
    }

    /// Returns the start page of a given Juz (1–30).
    func juzStartPage(_ juz: Int) -> Int {
        guard juz >= 1, juz <= 30 else { return 1 }
        return Self.juzStartPages[juz - 1]
    }

    // MARK: - Binary Search

    /// Returns the index of the last element in `sortedPages` that is ≤ `page`,
    /// plus whether `page` exactly equals that element.
    private static func rank(of page: Int, in sortedPages: [Int]) -> (index: Int, onBoundary: Bool) {
        guard !sortedPages.isEmpty else { return (0, false) }
        var lo = 0
        var hi = sortedPages.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if sortedPages[mid] <= page { lo = mid } else { hi = mid - 1 }
        }
        return (index: lo, onBoundary: sortedPages[lo] == page)
    }
}
