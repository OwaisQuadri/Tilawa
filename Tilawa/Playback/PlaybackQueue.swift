import Foundation

/// Builds the flat ordered list of AyahRefs for a playback session.
/// Accounts for connection ayaat before/after the main range.
enum PlaybackQueue {

    /// Returns the full ordered ayah list for a playback session.
    ///
    /// - Parameters:
    ///   - range: The main range the user wants to play.
    ///   - settings: Immutable snapshot captured at play() time.
    ///   - metadata: Quran metadata service for navigation.
    static func build(range: AyahRange,
                      settings: PlaybackSettingsSnapshot,
                      metadata: QuranMetadataService) -> [AyahRef] {
        var queue: [AyahRef] = []

        // Connection ayah before the range
        if settings.connectionAyahBefore > 0,
           let prev = metadata.ayah(before: range.start) {
            queue.append(prev)
        }

        // Main range
        var cursor = range.start
        while cursor <= range.end {
            queue.append(cursor)
            guard let next = metadata.ayah(after: cursor) else { break }
            cursor = next
        }

        // Connection ayah after the range
        if settings.connectionAyahAfter > 0,
           let next = metadata.ayah(after: range.end) {
            queue.append(next)
        }

        return queue
    }

    /// Builds a continuation queue starting from `startRef` for N ayaat.
    static func buildContinuation(from startRef: AyahRef,
                                   count: Int,
                                   metadata: QuranMetadataService) -> [AyahRef] {
        var queue: [AyahRef] = []
        var cursor: AyahRef? = startRef
        for _ in 0..<count {
            guard let ref = cursor else { break }
            queue.append(ref)
            cursor = metadata.ayah(after: ref)
        }
        return queue
    }

    /// Builds a continuation queue covering N pages starting from the appropriate page boundary.
    /// If `endRef` is the last ayah on its page, starts from the next page.
    /// If `endRef` is mid-page, starts from the beginning of the current page.
    /// Uses exact page layout data instead of page estimation.
    /// If `extraAyah` is true, appends one additional ayah after the last page.
    static func buildPageContinuation(after endRef: AyahRef,
                                       pageCount: Int,
                                       extraAyah: Bool = false,
                                       metadata: QuranMetadataService) async -> [AyahRef] {
        let endPage = await metadata.exactPage(for: endRef)
        let isAtPageEnd: Bool
        if let endPageRange = await metadata.exactAyahRange(for: endPage) {
            isAtPageEnd = endRef >= endPageRange.last
        } else {
            isAtPageEnd = false
        }

        let startPage = isAtPageEnd ? endPage + 1 : endPage
        let lastPage = min(startPage + pageCount - 1, 604)
        guard startPage <= lastPage else { return [] }

        var queue: [AyahRef] = []
        for p in startPage...lastPage {
            guard let pageRange = await metadata.exactAyahRange(for: p) else { break }
            var cursor: AyahRef? = pageRange.first
            while let ref = cursor {
                queue.append(ref)
                if ref >= pageRange.last { break }
                cursor = metadata.ayah(after: ref)
            }
        }

        if extraAyah, let last = queue.last, let next = metadata.ayah(after: last) {
            queue.append(next)
        }

        return queue
    }
}

// MARK: - QuranMetadataService extensions needed by PlaybackQueue

extension QuranMetadataService {
    /// Returns the exact first and last ayah on a page using rendered page layout data.
    func exactAyahRange(for page: Int) async -> (first: AyahRef, last: AyahRef)? {
        guard let layout = try? await PageLayoutProvider.shared.layout(for: page) else { return nil }
        let words = layout.lines.compactMap(\.words).flatMap { $0 }
        guard let first = words.first?.ayahRef, let last = words.last?.ayahRef else { return nil }
        return (first, last)
    }

    /// Returns the exact page number for a given ayah using rendered page layout data.
    /// Uses the estimated page as a starting hint, then verifies against actual boundaries.
    func exactPage(for ref: AyahRef) async -> Int {
        let estimated = page(for: ref)
        for delta in [0, 1, -1, 2, -2] {
            let candidate = estimated + delta
            guard (1...604).contains(candidate) else { continue }
            guard let range = await exactAyahRange(for: candidate) else { continue }
            if ref >= range.first && ref <= range.last { return candidate }
        }
        return estimated
    }
}
