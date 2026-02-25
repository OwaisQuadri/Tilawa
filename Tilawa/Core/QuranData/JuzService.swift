import Foundation

struct JuzInfo {
    let juz: Int          // 1–30
    let hizb: Int         // 1–60
    let thumunInHizb: Int // 1–4 (quarter within the hizb)
    let isOnThumunBoundary: Bool  // true if this page starts a new thumun segment
}

/// Provides Juz, Hizb, and Thumun info for any Mushaf page.
///
/// Juz boundaries are hardcoded for the 604-page Al-Madinah Mushaf.
/// Hizb and Thumun positions are derived proportionally within each Juz
/// (each Juz = 2 Hizb = 8 Thumun).
final class JuzService: Sendable {
    static let shared = JuzService()

    /// Start page of each Juz (index 0 = Juz 1). Al-Madinah 604-page mushaf.
    static let juzStartPages: [Int] = [
        1,   // Juz 1
        22,  // Juz 2
        42,  // Juz 3
        62,  // Juz 4
        82,  // Juz 5
        102, // Juz 6
        121, // Juz 7
        142, // Juz 8
        162, // Juz 9
        182, // Juz 10
        201, // Juz 11
        222, // Juz 12
        242, // Juz 13
        261, // Juz 14
        282, // Juz 15
        302, // Juz 16
        322, // Juz 17
        342, // Juz 18
        362, // Juz 19
        381, // Juz 20
        402, // Juz 21
        422, // Juz 22
        442, // Juz 23
        462, // Juz 24
        482, // Juz 25
        502, // Juz 26
        522, // Juz 27
        542, // Juz 28
        562, // Juz 29
        582, // Juz 30
    ]

    func juzInfo(forPage page: Int) -> JuzInfo {
        // Determine Juz (1-indexed)
        var juz = 1
        for (i, startPage) in Self.juzStartPages.enumerated() {
            if page >= startPage { juz = i + 1 }
        }

        let juzStart = Self.juzStartPages[juz - 1]
        let juzEnd   = juz < 30 ? Self.juzStartPages[juz] - 1 : 604
        let juzPages = max(juzEnd - juzStart + 1, 1)
        let offset   = page - juzStart  // 0-indexed within Juz

        let fraction = Double(offset) / Double(juzPages)

        // Hizb: 2 per Juz → value 1-60
        let hizbInJuz = Int(fraction * 2.0)  // 0 or 1
        let hizb = (juz - 1) * 2 + hizbInJuz + 1

        // Thumun: 4 per Hizb = 8 per Juz → value 1-4
        let thumunInJuz   = Int(fraction * 8.0)  // 0-7
        let thumunInHizb  = thumunInJuz % 4 + 1  // 1-4

        // Detect thumun boundary: current thumun index differs from previous page
        let prevFraction    = offset > 0 ? Double(offset - 1) / Double(juzPages) : -1.0
        let prevThumunInJuz = offset > 0 ? Int(prevFraction * 8.0) : -1
        let onBoundary      = thumunInJuz != prevThumunInJuz

        return JuzInfo(
            juz: juz,
            hizb: hizb,
            thumunInHizb: thumunInHizb,
            isOnThumunBoundary: onBoundary
        )
    }

    /// Returns the Juz number (1-30) for a given page.
    func juz(forPage page: Int) -> Int {
        juzInfo(forPage: page).juz
    }
}
