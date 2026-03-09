import Foundation

/// Provides fuzzy Arabic text search across all ayahs in the Quran.
///
/// Builds an in-memory index on first use, supporting two search modes:
/// - **Arabic input**: diacritics-stripped substring matching against the consonantal skeleton
/// - **Latin input**: transliteration-based matching (e.g. "alHamdu" finds 1:2)
///
/// Results are ranked by relevance: word-boundary matches first, then by coverage
/// (query length / ayah length), with exact matches always above fuzzy matches.
final class ArabicTextSearchService: @unchecked Sendable {

    static let shared = ArabicTextSearchService()

    // MARK: - Types

    struct SearchHit {
        let ayahRef: AyahRef
        /// Text before the match, potentially prefixed with "… " if truncated.
        let before: String
        /// The matched portion of the ayah text (to bold).
        let match: String
        /// Text after the match, potentially suffixed with " …" if truncated.
        let after: String
    }

    // MARK: - Private State

    private let lock = NSLock()
    private var index: [(ref: AyahRef, stripped: String, romanized: String, original: String)]?

    // MARK: - Public API

    /// Searches Hafs ayah text for a substring match.
    /// Results are ranked by relevance (word-boundary, coverage, exact > fuzzy).
    func search(_ query: String, limit: Int = 15) -> [SearchHit] {
        let isArabic = query.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }

        let normalizedQuery: String
        let keyPath: KeyPath<(ref: AyahRef, stripped: String, romanized: String, original: String), String>

        if isArabic {
            normalizedQuery = stripTashkeel(query)
            keyPath = \.stripped
        } else {
            normalizedQuery = query.replacingOccurrences(of: "'", with: "3")
            keyPath = \.romanized
        }

        guard !normalizedQuery.isEmpty else { return [] }

        let entries = buildIndex()
        let maxDist = normalizedQuery.count >= 4 ? max(1, normalizedQuery.count / 5) : 0

        // Collect scored hits
        var scoredExact: [(hit: SearchHit, score: Double)] = []
        var scoredFuzzy: [(hit: SearchHit, score: Double)] = []
        // Collect more candidates than limit so sorting is meaningful
        let collectLimit = limit * 5

        for entry in entries {
            let field = entry[keyPath: keyPath]

            if isArabic {
                if let range = field.range(of: normalizedQuery) {
                    let score = relevanceScore(field: field, matchRange: range, queryLength: normalizedQuery.count)
                    let hit = buildHit(entry: entry, field: field, matchRange: range, isArabic: true)
                    scoredExact.append((hit, score))
                } else if maxDist > 0 && scoredFuzzy.count < collectLimit
                            && fuzzySubstringMatch(text: field, query: normalizedQuery, maxDistance: maxDist) {
                    let hit = SearchHit(ayahRef: entry.ref, before: "", match: "", after: entry.original)
                    scoredFuzzy.append((hit, 0))
                }
            } else {
                if let range = field.range(of: normalizedQuery, options: .caseInsensitive) {
                    let score = relevanceScore(field: field, matchRange: range, queryLength: normalizedQuery.count)
                    let hit = buildHit(entry: entry, field: field, matchRange: range, isArabic: false)
                    scoredExact.append((hit, score))
                } else if maxDist > 0 && scoredFuzzy.count < collectLimit
                            && fuzzySubstringMatch(text: field.lowercased(), query: normalizedQuery.lowercased(), maxDistance: maxDist) {
                    let hit = SearchHit(ayahRef: entry.ref, before: "", match: "", after: entry.original)
                    scoredFuzzy.append((hit, 0))
                }
            }
            if scoredExact.count >= collectLimit { break }
        }

        // Sort exact hits by score (highest first), then append fuzzy
        scoredExact.sort { $0.score > $1.score }
        let ranked = scoredExact.map(\.hit) + scoredFuzzy.map(\.hit)
        return Array(ranked.prefix(limit))
    }

    // MARK: - Relevance Scoring

    /// Scores a match for ranking. Higher = more relevant.
    ///
    /// Factors:
    /// - **Coverage**: query length / field length (0–1). Longer matches relative to ayah rank higher.
    /// - **Word boundary**: +0.5 if match starts at a word boundary (start of string or after space).
    /// - **Full word**: +0.3 if match also ends at a word boundary.
    private func relevanceScore(field: String, matchRange: Range<String.Index>, queryLength: Int) -> Double {
        let fieldLength = field.count
        guard fieldLength > 0 else { return 0 }

        var score = Double(queryLength) / Double(fieldLength)

        // Word-boundary bonus at start
        if matchRange.lowerBound == field.startIndex {
            score += 0.5
        } else {
            let charBefore = field[field.index(before: matchRange.lowerBound)]
            if charBefore == " " { score += 0.5 }
        }

        // Word-boundary bonus at end
        if matchRange.upperBound == field.endIndex {
            score += 0.3
        } else {
            let charAfter = field[matchRange.upperBound]
            if charAfter == " " { score += 0.3 }
        }

        return score
    }

    // MARK: - Hit Building

    private typealias Entry = (ref: AyahRef, stripped: String, romanized: String, original: String)

    /// Maps a match range in the stripped/romanized field back to the original Arabic text,
    /// then splits the original into (before, match, after) with truncation.
    private func buildHit(entry: Entry, field: String, matchRange: Range<String.Index>, isArabic: Bool) -> SearchHit {
        let original = entry.original

        let fieldMatchStart = field.distance(from: field.startIndex, to: matchRange.lowerBound)
        let fieldMatchEnd = field.distance(from: field.startIndex, to: matchRange.upperBound)

        let origRange: (start: String.Index, end: String.Index)
        if isArabic {
            origRange = mapStrippedToOriginal(original: original, matchStart: fieldMatchStart, matchEnd: fieldMatchEnd)
        } else {
            origRange = mapRomanizedToOriginal(original: original, romanized: field, matchStart: fieldMatchStart, matchEnd: fieldMatchEnd)
        }

        let fullBefore = String(original[original.startIndex..<origRange.start])
        let matchText = String(original[origRange.start..<origRange.end])
        let fullAfter = String(original[origRange.end..<original.endIndex])

        let maxBefore = 20
        let maxAfter = 40
        let before: String
        let after: String

        if fullBefore.count > maxBefore {
            let startIdx = fullBefore.index(fullBefore.endIndex, offsetBy: -maxBefore)
            before = "… " + fullBefore[startIdx...]
        } else {
            before = fullBefore
        }

        if fullAfter.count > maxAfter {
            let endIdx = fullAfter.index(fullAfter.startIndex, offsetBy: maxAfter)
            after = fullAfter[..<endIdx] + " …"
        } else {
            after = fullAfter
        }

        return SearchHit(ayahRef: entry.ref, before: before, match: matchText, after: after)
    }

    private func mapStrippedToOriginal(original: String, matchStart: Int, matchEnd: Int) -> (start: String.Index, end: String.Index) {
        var strippedCount = 0
        var origStart = original.startIndex
        var origEnd = original.endIndex

        for idx in original.indices {
            let c = original[idx]
            let dominated = c.unicodeScalars.allSatisfy { isStrippable($0.value) }
            if dominated { continue }

            if strippedCount == matchStart {
                origStart = idx
            }
            strippedCount += 1
            if strippedCount == matchEnd {
                origEnd = original.index(after: idx)
                break
            }
        }
        return (origStart, origEnd)
    }

    private func mapRomanizedToOriginal(original: String, romanized: String, matchStart: Int, matchEnd: Int) -> (start: String.Index, end: String.Index) {
        let romanWords = romanized.split(separator: " ", omittingEmptySubsequences: false)
        let origWords = original.split(separator: " ", omittingEmptySubsequences: false)

        guard romanWords.count == origWords.count, !romanWords.isEmpty else {
            return (original.startIndex, original.endIndex)
        }

        var charPos = 0
        var startWord = 0
        var endWord = romanWords.count - 1

        for (i, word) in romanWords.enumerated() {
            let wordStart = charPos
            let wordEnd = charPos + word.count
            if matchStart >= wordStart && matchStart < wordEnd + 1 {
                startWord = i
            }
            if matchEnd > wordStart && matchEnd <= wordEnd + 1 {
                endWord = i
                break
            }
            charPos = wordEnd + 1
        }

        let origStart = origWords[startWord].startIndex
        let origEnd = origWords[endWord].endIndex
        return (origStart, origEnd)
    }

    private func isStrippable(_ v: UInt32) -> Bool {
        if (0x064B...0x0652).contains(v) { return true }
        if v == 0x0670 { return true }
        if (0x06D6...0x06ED).contains(v) { return true }
        if v == 0x0640 { return true }
        if v == 0x06E5 || v == 0x06E6 { return true }
        if v == 0x0615 || v == 0x0616 || v == 0x0617 { return true }
        if v == 0x065F { return true }
        return false
    }

    // MARK: - Fuzzy Matching

    private func fuzzySubstringMatch(text: String, query: String, maxDistance: Int) -> Bool {
        let t = Array(text.unicodeScalars)
        let q = Array(query.unicodeScalars)
        let n = t.count
        let m = q.count

        guard m > 0, n > 0 else { return false }

        var dp = Array(0...m)

        for i in 1...n {
            var prev = 0
            dp[0] = 0
            for j in 1...m {
                let old = dp[j]
                if t[i - 1] == q[j - 1] {
                    dp[j] = prev
                } else {
                    dp[j] = min(prev, min(old, dp[j - 1])) + 1
                }
                prev = old
            }
            if dp[m] <= maxDistance {
                return true
            }
        }
        return false
    }

    // MARK: - Arabic Normalization

    func stripTashkeel(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.unicodeScalars.count)

        for scalar in text.unicodeScalars {
            let v = scalar.value
            if isStrippable(v) { continue }

            if v == 0x0623 || v == 0x0625 || v == 0x0622 || v == 0x0671 {
                result.append("\u{0627}")
                continue
            }
            if v == 0x0629 {
                result.append("\u{0647}")
                continue
            }

            result.append(Character(scalar))
        }
        return result
    }

    // MARK: - Romanization

    private static let romanMap: [UInt32: String] = [
        0x0627: "a", 0x0628: "b", 0x062A: "t", 0x062B: "th",
        0x062C: "j", 0x062D: "H", 0x062E: "kh", 0x062F: "d",
        0x0630: "dh", 0x0631: "r", 0x0632: "z", 0x0633: "s",
        0x0634: "sh", 0x0635: "S", 0x0636: "D", 0x0637: "T",
        0x0638: "Z", 0x0639: "3", 0x063A: "gh", 0x0641: "f",
        0x0642: "q", 0x0643: "k", 0x0644: "l", 0x0645: "m",
        0x0646: "n", 0x0647: "h", 0x0648: "w", 0x064A: "y",
        0x0629: "h", 0x0649: "a", 0x0621: "", 0x0671: "a",
        0x0623: "a", 0x0625: "i", 0x0622: "a", 0x0624: "w",
        0x0626: "y",
    ]

    private static func isDiacritic(_ v: UInt32) -> Bool {
        (0x064B...0x0652).contains(v) || v == 0x0670
            || (0x06D6...0x06ED).contains(v) || v == 0x0640
            || v == 0x06E5 || v == 0x06E6
            || v == 0x0615 || v == 0x0616 || v == 0x0617
            || v == 0x065F
    }

    private func romanize(_ text: String) -> String {
        var expanded: [Unicode.Scalar] = []
        var lastBase: Unicode.Scalar?
        var lastBaseIndex: Int = 0

        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v == 0x0651 {
                if let base = lastBase {
                    expanded.insert(base, at: lastBaseIndex + 1)
                }
            } else {
                expanded.append(scalar)
                if !Self.isDiacritic(v) && v != 0x0020 {
                    lastBase = scalar
                    lastBaseIndex = expanded.count - 1
                }
            }
        }

        var result = ""
        result.reserveCapacity(expanded.count)
        var prevVowel = ""

        for scalar in expanded {
            let v = scalar.value

            switch v {
            case 0x064E: result += "a"; prevVowel = "a"; continue
            case 0x0650: result += "i"; prevVowel = "i"; continue
            case 0x064F: result += "u"; prevVowel = "u"; continue
            case 0x0670: result += "a"; continue
            case 0x064B: result += "an"; prevVowel = ""; continue
            case 0x064D: result += "in"; prevVowel = ""; continue
            case 0x064C: result += "un"; prevVowel = ""; continue
            case 0x0652: prevVowel = ""; continue
            default: break
            }

            if Self.isDiacritic(v) { continue }

            if let mapped = Self.romanMap[v] {
                if v == 0x064A && prevVowel == "i" {
                    result += "i"
                } else if v == 0x0648 && prevVowel == "u" {
                    result += "u"
                } else {
                    result += mapped
                }
                prevVowel = ""
                continue
            }

            if v == 0x0020 {
                result += " "
                prevVowel = ""
            }
        }
        return result
    }

    // MARK: - Index

    private func buildIndex() -> [(ref: AyahRef, stripped: String, romanized: String, original: String)] {
        lock.lock()
        defer { lock.unlock() }

        if let cached = index { return cached }

        let textService = RiwayahTextService.shared
        let metadata = QuranMetadataService.shared
        var entries: [(ref: AyahRef, stripped: String, romanized: String, original: String)] = []
        entries.reserveCapacity(6236)

        for surah in metadata.surahs {
            let ayahs = textService.ayahs(surah: surah.number, riwayah: .hafs)
            for (i, text) in ayahs.enumerated() {
                let ref = AyahRef(surah: surah.number, ayah: i + 1)
                let stripped = stripTashkeel(text)
                let romanized = romanize(text)
                entries.append((ref: ref, stripped: stripped, romanized: romanized, original: text))
            }
        }

        index = entries
        return entries
    }
}
