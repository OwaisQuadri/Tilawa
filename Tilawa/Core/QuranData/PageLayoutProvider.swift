import Foundation

/// Loads and caches QUL page layout data from bundled JSON files.
actor PageLayoutProvider {
    static let shared = PageLayoutProvider()

    private var cache: [Int: QULPageLayout] = [:]

    /// Load layout for a specific page (1-604). Returns from cache if available.
    func layout(for page: Int) throws -> QULPageLayout {
        if let cached = cache[page] { return cached }

        let fileName = String(format: "page%03d", page)
        guard let url = Bundle.main.url(forResource: fileName,
                                         withExtension: "json") else {
            throw QuranDataError.pageNotFound(page)
        }
        let data = try Data(contentsOf: url)
        let layout = try JSONDecoder().decode(QULPageLayout.self, from: data)
        cache[page] = layout
        return layout
    }

    /// Evict pages outside a window to control memory.
    func evict(outside range: ClosedRange<Int>) {
        cache = cache.filter { range.contains($0.key) }
    }

    /// Clear entire cache.
    func clearCache() {
        cache.removeAll()
    }

    /// Number of cached pages (for testing).
    var cacheCount: Int { cache.count }
}
