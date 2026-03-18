import Foundation

/// Content to render on a mushaf page for a non-Hafs riwayah.
struct RiwayahPageContent: Sendable {
    let page: Int
    let riwayah: Riwayah
    let elements: [RiwayahPageElement]

    /// All ayah refs (native numbering) present on this page.
    var ayahRefs: [AyahRef] {
        elements.compactMap {
            if case .ayahText(let surah, let nativeAyah, _) = $0 {
                return AyahRef(surah: surah, ayah: nativeAyah)
            }
            return nil
        }
    }
}

/// A single renderable element on a non-Hafs mushaf page.
enum RiwayahPageElement: Sendable {
    case surahHeader(surahNumber: Int)
    case basmala
    case ayahText(surah: Int, nativeAyah: Int, text: String)
}

/// Builds non-Hafs page content by mapping Hafs QUL layouts through the offset and text services.
actor RiwayahPageLayoutBuilder {
    static let shared = RiwayahPageLayoutBuilder()

    private var cache: [CacheKey: RiwayahPageContent] = [:]

    private struct CacheKey: Hashable {
        let page: Int
        let riwayah: Riwayah
    }

    /// Build page content for a non-Hafs riwayah.
    func build(page: Int, riwayah: Riwayah) async throws -> RiwayahPageContent {
        let key = CacheKey(page: page, riwayah: riwayah)
        if let cached = cache[key] { return cached }

        let layout = try await PageLayoutProvider.shared.layout(for: page)
        let content = Self.buildContent(from: layout, riwayah: riwayah)
        cache[key] = content
        return content
    }

    /// Evict pages outside a window.
    func evict(outside range: ClosedRange<Int>) {
        cache = cache.filter { range.contains($0.key.page) }
    }

    // MARK: - Building

    private static func buildContent(from layout: QULPageLayout, riwayah: Riwayah) -> RiwayahPageContent {
        let offsetService = AyahOffsetService.shared
        let textService = RiwayahTextService.shared

        var elements: [RiwayahPageElement] = []
        // Track emitted native refs to handle merged ayahs (e.g. Hafs 2:1+2:2 → Warsh 2:1).
        // When multiple Hafs positions map to the same native ayah, concatenate their text.
        var emittedNativeRefs = Set<AyahRef>()
        // Track emitted Hafs refs to avoid self-duplication when the same ayah spans multiple QUL lines.
        var emittedHafsRefs = Set<AyahRef>()

        for line in layout.lines {
            switch line.type {
            case .surahHeader:
                let surahNum = Int(line.surah ?? "1") ?? 1
                elements.append(.surahHeader(surahNumber: surahNum))

            case .basmala:
                elements.append(.basmala)

            case .text:
                guard let words = line.words else { continue }
                // Collect distinct Hafs ayah refs on this line (preserving order)
                var lineHafsRefs: [AyahRef] = []
                for word in words {
                    let ref = word.ayahRef
                    if lineHafsRefs.last != ref {
                        lineHafsRefs.append(ref)
                    }
                }

                for hafsRef in lineHafsRefs {
                    // Skip if this exact Hafs ref was already processed on a previous line
                    guard !emittedHafsRefs.contains(hafsRef) else { continue }
                    emittedHafsRefs.insert(hafsRef)

                    // Get native ayah number (nil = no equivalent in this riwayah)
                    guard let nativeAyah = offsetService.nativeAyah(for: hafsRef, riwayah: riwayah) else {
                        // Fatiha Basmala fallback: if Hafs 1:1 (the Basmala) has no native
                        // equivalent (riwayah doesn't count it as a numbered ayah), show the
                        // ornamental Basmala so it's still visible.
                        if hafsRef.surah == 1 && hafsRef.ayah == 1 {
                            elements.append(.basmala)
                        }
                        continue
                    }
                    let nativeRef = AyahRef(surah: hafsRef.surah, ayah: nativeAyah)

                    // Text service uses Hafs indexing (6236 positions for all riwayahs)
                    guard let text = textService.text(for: hafsRef, riwayah: riwayah) else {
                        continue
                    }

                    if emittedNativeRefs.contains(nativeRef) {
                        // Merged ayah: append text to the previously emitted element
                        if let lastIdx = elements.indices.last(where: {
                            if case .ayahText(nativeRef.surah, nativeRef.ayah, _) = elements[$0] { return true }
                            return false
                        }), case .ayahText(let s, let a, let existing) = elements[lastIdx] {
                            elements[lastIdx] = .ayahText(surah: s, nativeAyah: a, text: existing + " " + text)
                        }
                    } else {
                        emittedNativeRefs.insert(nativeRef)
                        elements.append(.ayahText(surah: hafsRef.surah, nativeAyah: nativeAyah, text: text))
                    }
                }
            }
        }

        return RiwayahPageContent(page: layout.page, riwayah: riwayah, elements: elements)
    }
}
