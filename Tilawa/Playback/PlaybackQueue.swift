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

    /// Builds a continuation queue covering the next N pages starting from the page after `endRef`.
    static func buildPageContinuation(after endRef: AyahRef,
                                       pageCount: Int,
                                       metadata: QuranMetadataService) -> [AyahRef] {
        let endPage = metadata.page(for: endRef)
        let startPage = endPage + 1
        let lastPage = min(startPage + pageCount - 1, 604)
        guard startPage <= lastPage else { return [] }

        var queue: [AyahRef] = []
        var cursor: AyahRef? = metadata.firstAyahOnPage(startPage)
        let lastAyahOnLastPage = metadata.lastAyahOnPage(lastPage)

        while let ref = cursor {
            queue.append(ref)
            if let last = lastAyahOnLastPage, ref >= last { break }
            cursor = metadata.ayah(after: ref)
        }
        return queue
    }
}

// MARK: - QuranMetadataService extensions needed by PlaybackQueue

extension QuranMetadataService {
    /// Returns the first ayah on a given page (1–604), or nil if out of range.
    func firstAyahOnPage(_ page: Int) -> AyahRef? {
        guard let surahInfo = surahOnPage(page) else { return nil }
        // Find the first ayah of the surah that starts on or after this page
        // For surahs spanning multiple pages, walk forward until we reach the right page
        var ref = AyahRef(surah: surahInfo.number, ayah: 1)
        while self.page(for: ref) < page {
            guard let next = ayah(after: ref) else { return nil }
            ref = next
        }
        return ref
    }

    /// Returns the last ayah on a given page (1–604), or nil if out of range.
    func lastAyahOnPage(_ page: Int) -> AyahRef? {
        guard let firstOnNext = firstAyahOnPage(page + 1) else {
            // page 604 — last ayah of the Quran
            return AyahRef(surah: 114, ayah: ayahCount(surah: 114))
        }
        return ayah(before: firstOnNext)
    }
}
