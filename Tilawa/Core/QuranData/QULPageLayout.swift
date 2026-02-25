import Foundation

/// Decoded from pageNNN.json — represents a single Mushaf page.
struct QULPageLayout: Codable, Sendable {
    let page: Int
    let lines: [QULLine]
}

/// A single line on a Mushaf page.
struct QULLine: Codable, Sendable {
    let line: Int
    let type: QULLineType
    let text: String?
    let surah: String?
    let verseRange: String?
    let words: [QULWord]?

    // Basmala lines have qpcV2/qpcV1 at the line level instead of words
    let qpcV2: String?
    let qpcV1: String?
}

enum QULLineType: String, Codable, Sendable {
    case surahHeader = "surah-header"
    case basmala = "basmala"
    case text = "text"
}

/// A single word on a Mushaf page.
struct QULWord: Codable, Sendable {
    let location: String   // "surah:ayah:wordIndex"
    let word: String       // Standard Arabic Unicode text
    let qpcV2: String?
    let qpcV1: String?

    /// Parsed ayah reference from the location string.
    var ayahRef: AyahRef {
        let parts = location.split(separator: ":").compactMap { Int($0) }
        return AyahRef(surah: parts[0], ayah: parts[1])
    }

    /// Word index within the ayah.
    var wordIndex: Int {
        let parts = location.split(separator: ":").compactMap { Int($0) }
        return parts.count >= 3 ? parts[2] : 0
    }
}
