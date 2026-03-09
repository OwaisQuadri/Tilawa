import SwiftUI
import SwiftData

/// Sheet for jumping to a specific surah/ayah, page, juz, or hizb position.
/// Three tabs: Position (wheel pickers) | Bookmarks | Recents
///
/// Sync architecture (Position tab):
///   - selectedSurah, selectedAyah, selectedPage are @State (direct picker bindings)
///   - Juz and Hizb pickers use custom Bindings derived from selectedPage to avoid cascades
///   - onChange(surah) guards against re-firing when surah was set programmatically from a page change
struct JumpToAyahSheet: View {
    @Environment(MushafViewModel.self) private var mushafVM
    @Environment(\.modelContext) private var modelContext

    @State private var selectedSurah: Int = 1
    @State private var selectedAyah: Int = 1
    @State private var selectedPage: Int = 1
    @AppStorage("jumpSheet.tab") private var selectedTab: JumpTab = .position
    @State private var searchText: String = ""
    @AppStorage("jumpSheet.bookmarkSort") private var bookmarkSort: BookmarkSort = .newest
    @AppStorage("jumpSheet.recentSearches") private var recentSearchesData: Data = Data()

    @Query(sort: \UserBookmark.createdAt, order: .reverse)
    private var bookmarks: [UserBookmark]

    @Query(sort: \ListeningSession.lastUpdated, order: .reverse)
    private var sessions: [ListeningSession]

    @Query(sort: \JumpHistory.timestamp, order: .reverse)
    private var jumpHistory: [JumpHistory]

    private let metadata = QuranMetadataService.shared
    private let juzService = JuzService.shared

    private enum JumpTab: String, CaseIterable {
        case position = "Position"
        case bookmarks = "Bookmarks"
        case recents = "Recents"
    }

    private enum BookmarkSort: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case position = "Position"
    }

    // MARK: - Recent Searches

    private var recentSearches: [String] {
        (try? JSONDecoder().decode([String].self, from: recentSearchesData)) ?? []
    }

    private func recordRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var searches = recentSearches
        searches.removeAll { $0 == trimmed }
        searches.insert(trimmed, at: 0)
        if searches.count > 10 { searches = Array(searches.prefix(10)) }
        recentSearchesData = (try? JSONEncoder().encode(searches)) ?? Data()
    }

    private func clearRecentSearches() {
        recentSearchesData = Data()
    }

    // MARK: - Jump Helpers

    private func recordAndJump(surah: Int, ayah: Int) {
        let page = metadata.page(for: AyahRef(surah: surah, ayah: ayah))
        modelContext.insert(JumpHistory(surah: surah, ayah: ayah, page: page))
        try? modelContext.save()
        mushafVM.jumpTo(surah: surah, ayah: ayah)
    }

    private func recordAndJumpToPage(_ page: Int) {
        let surah = metadata.surahOnPage(page)
        modelContext.insert(JumpHistory(
            surah: surah?.number ?? 1,
            ayah: 1,
            page: page
        ))
        try? modelContext.save()
        mushafVM.jumpToPage(page)
    }

    // MARK: - Derived Bindings (no @State → no onChange cascade)

    private var juzBinding: Binding<Int> {
        Binding(
            get: { juzService.juz(forPage: selectedPage) },
            set: { newJuz in
                selectedPage = juzService.juzStartPage(newJuz)
            }
        )
    }

    /// Binding over thumun index (1–240). Each thumun = ¼ hizb.
    private var thumunBinding: Binding<Int> {
        Binding(
            get: { juzService.juzInfo(forPage: selectedPage).thumun },
            set: { newThumun in
                selectedPage = JuzService.thumunStartPages[newThumun - 1]
            }
        )
    }

    // MARK: - Helpers

    private func thumunLabel(_ t: Int) -> String {
        let hizb = (t - 1) / 4 + 1
        let fracs = ["", "¼", "½", "¾"]
        return "\(hizb)\(fracs[(t - 1) % 4])"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search surah, page, juz...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if !searchText.isEmpty {
                    searchResultsList
                } else {
                    if !recentSearches.isEmpty {
                        recentSearchesList
                    }
                    Picker("", selection: $selectedTab) {
                        ForEach(JumpTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    switch selectedTab {
                    case .position:
                        positionPickerContent
                    case .bookmarks:
                        bookmarksList
                    case .recents:
                        recentsList
                    }
                }
            }
            .navigationTitle("Jump to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if selectedTab == .position && searchText.isEmpty {
                        Button("Go") {
                            recordAndJump(surah: selectedSurah, ayah: selectedAyah)
                        }
                        .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { mushafVM.showJumpSheet = false }
                }
            }
            .onAppear {
                let page = mushafVM.currentPage
                selectedPage = page
                if let surah = metadata.surahOnPage(page) {
                    selectedSurah = surah.number
                }
                selectedAyah = 1
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Position Tab

    private var positionPickerContent: some View {
        HStack(spacing: 0) {
            // Surah picker
            VStack(spacing: 0) {
                Text("Surah").font(.caption).foregroundStyle(.secondary)
                Picker("Surah", selection: $selectedSurah) {
                    ForEach(metadata.surahs, id: \.number) { surah in
                        HStack {
                            Text("\(surah.number). \(surah.englishName)")
                                .font(.caption)
                            Spacer()
                            Text(surah.name)
                                .font(.caption2)
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                        .tag(surah.number)
                    }
                }
                .pickerStyle(.wheel)
                .onChange(of: selectedSurah) { _, newSurah in
                    // Guard: if current page already belongs to this surah, this was a
                    // programmatic update from onChange(page) — don't overwrite the page.
                    guard metadata.surahOnPage(selectedPage)?.number != newSurah else { return }
                    selectedAyah = 1
                    selectedPage = metadata.page(for: AyahRef(surah: newSurah, ayah: 1))
                }
            }

            Divider()

            // Ayah picker
            VStack(spacing: 0) {
                Text("Ayah").font(.caption).foregroundStyle(.secondary)
                Picker("Ayah", selection: $selectedAyah) {
                    let count = max(1, metadata.ayahCount(surah: selectedSurah))
                    ForEach(1...count, id: \.self) { ayah in
                        Text("\(ayah)")
                            .font(.caption)
                            .tag(ayah)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: 50)
                .id(selectedSurah) // Recreate wheel when surah changes so it scrolls to top
                .onChange(of: selectedAyah) { _, newAyah in
                    selectedPage = metadata.page(for: AyahRef(surah: selectedSurah, ayah: newAyah))
                }
            }

            Divider()

            // Page picker
            VStack(spacing: 0) {
                Text("Page").font(.caption).foregroundStyle(.secondary)
                Picker("Page", selection: $selectedPage) {
                    ForEach(1...604, id: \.self) { page in
                        Text("\(page)")
                            .font(.caption)
                            .tag(page)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: 50)
                .onChange(of: selectedPage) { _, newPage in
                    if let surah = metadata.surahOnPage(newPage) {
                        selectedSurah = surah.number
                        // Binary search for the first ayah of this surah on newPage
                        let count = metadata.ayahCount(surah: surah.number)
                        var lo = 1, hi = count
                        while lo < hi {
                            let mid = (lo + hi) / 2
                            if metadata.page(for: AyahRef(surah: surah.number, ayah: mid)) < newPage {
                                lo = mid + 1
                            } else {
                                hi = mid
                            }
                        }
                        selectedAyah = lo
                    } else {
                        selectedAyah = 1
                    }
                }
            }

            Divider()

            // Juz picker (custom Binding derived from selectedPage — no cascade)
            VStack(spacing: 0) {
                Text("Juz").font(.caption).foregroundStyle(.secondary)
                Picker("Juz", selection: juzBinding) {
                    ForEach(1...30, id: \.self) { juz in
                        Text("\(juz)")
                            .font(.caption)
                            .tag(juz)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: 50)
                .id(juzService.juz(forPage: selectedPage)) // Scroll when juz changes
            }

            Divider()

            // Hizb picker — each row = ¼ hizb (thumun), 240 total
            VStack(spacing: 0) {
                Text("Hizb").font(.caption).foregroundStyle(.secondary)
                Picker("Hizb", selection: thumunBinding) {
                    ForEach(1...240, id: \.self) { t in
                        Text(thumunLabel(t))
                            .font(.caption)
                            .tag(t)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: 50)
                .id(juzService.juzInfo(forPage: selectedPage).thumun) // Scroll when thumun changes
            }
        }
    }

    // MARK: - Bookmarks Tab

    private var sortedBookmarks: [UserBookmark] {
        switch bookmarkSort {
        case .newest:
            return bookmarks // already sorted by createdAt desc via @Query
        case .oldest:
            return bookmarks.reversed()
        case .position:
            return bookmarks.sorted { $0.safeAyahRef < $1.safeAyahRef }
        }
    }

    private var bookmarksList: some View {
        Group {
            if bookmarks.isEmpty {
                ContentUnavailableView(
                    "No Bookmarks",
                    systemImage: "bookmark",
                    description: Text("Long-press an ayah to add a bookmark.")
                )
            } else {
                VStack(spacing: 0) {
                    Picker("Sort", selection: $bookmarkSort) {
                        ForEach(BookmarkSort.allCases, id: \.self) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                    List {
                        ForEach(sortedBookmarks, id: \.self) { bookmark in
                            Button {
                                recordAndJump(
                                    surah: bookmark.safeAyahRef.surah,
                                    ayah: bookmark.safeAyahRef.ayah
                                )
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        if !bookmark.safeLabel.isEmpty {
                                            Text(bookmark.safeLabel)
                                                .font(.subheadline.weight(.medium))
                                        }
                                        Text("\(metadata.surahName(bookmark.safeAyahRef.surah)) \(bookmark.safeAyahRef.surah):\(bookmark.safeAyahRef.ayah)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("p. \(bookmark.safePage)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            let sorted = sortedBookmarks
                            for index in offsets {
                                modelContext.delete(sorted[index])
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    // MARK: - Search

    private enum SearchResult: Identifiable {
        case page(Int)
        case juz(Int, startPage: Int)
        case surahAyah(surah: Int, ayah: Int, label: String)
        case ayahText(surah: Int, ayah: Int, label: String, hit: ArabicTextSearchService.SearchHit)

        var id: String {
            switch self {
            case .page(let p): return "p-\(p)"
            case .juz(let j, _): return "j-\(j)"
            case .surahAyah(let s, let a, _): return "sa-\(s)-\(a)"
            case .ayahText(let s, let a, _, _): return "at-\(s)-\(a)"
            }
        }
    }

    private var searchResults: [SearchResult] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        var results: [SearchResult] = []

        // "p 100" / "page 100" / "pg 100" → page
        for prefix in ["p ", "page ", "pg "] {
            if lower.hasPrefix(prefix),
               let n = Int(lower.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)),
               (1...604).contains(n) {
                results.append(.page(n))
            }
        }

        // "j 2" / "juz 2" / "juz' 2" → juz
        for prefix in ["j ", "juz ", "juz' "] {
            if lower.hasPrefix(prefix),
               let n = Int(lower.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)),
               (1...30).contains(n) {
                results.append(.juz(n, startPage: juzService.juzStartPage(n)))
            }
        }

        // "10:10" → surah:ayah
        let colonParts = trimmed.split(separator: ":")
        if colonParts.count == 2,
           let s = Int(colonParts[0]), let a = Int(colonParts[1]),
           (1...114).contains(s), a >= 1, a <= metadata.ayahCount(surah: s) {
            results.append(.surahAyah(
                surah: s, ayah: a,
                label: "\(metadata.surahName(s)) \(s):\(a)"
            ))
        }

        // Bare number N → page, surah, juz, and all surahs with ayah N
        if let n = Int(trimmed) {
            if (1...604).contains(n) && !results.contains(where: { if case .page = $0 { true } else { false } }) {
                results.append(.page(n))
            }
            if (1...114).contains(n) {
                results.append(.surahAyah(
                    surah: n, ayah: 1,
                    label: "\(metadata.surahName(n)) \(n):1"
                ))
            }
            if (1...30).contains(n) && !results.contains(where: { if case .juz = $0 { true } else { false } }) {
                results.append(.juz(n, startPage: juzService.juzStartPage(n)))
            }
            // Every surah that has ayah N
            for surah in metadata.surahs where surah.ayahCount >= n && n > 1 {
                results.append(.surahAyah(
                    surah: surah.number, ayah: n,
                    label: "\(surah.englishName) \(surah.number):\(n)"
                ))
            }
        }

        // "10 10" (two numbers separated by space) → surah:ayah
        let spaceParts = trimmed.split(separator: " ")
        if spaceParts.count == 2,
           let s = Int(spaceParts[0]), let a = Int(spaceParts[1]),
           (1...114).contains(s), a >= 1, a <= metadata.ayahCount(surah: s) {
            let id = "sa-\(s)-\(a)"
            if !results.contains(where: { $0.id == id }) {
                results.append(.surahAyah(
                    surah: s, ayah: a,
                    label: "\(metadata.surahName(s)) \(s):\(a)"
                ))
            }
        }

        // Fuzzy surah name matching (e.g. "yunus", "kahf", "al-baqarah")
        let surahMatches = metadata.searchSurahs(trimmed)
        for surah in surahMatches.prefix(5) {
            let ayah = parseTrailingAyah(trimmed, surahName: surah.englishName)
            let clampedAyah = min(ayah, surah.ayahCount)
            let id = "sa-\(surah.number)-\(clampedAyah)"
            if !results.contains(where: { $0.id == id }) {
                results.append(.surahAyah(
                    surah: surah.number, ayah: clampedAyah,
                    label: "\(surah.englishName) \(surah.number):\(clampedAyah)"
                ))
            }
        }

        // Ayah text search — works with both Arabic and Latin (transliteration) input
        if trimmed.count >= 3 {
            let hits = ArabicTextSearchService.shared.search(trimmed)
            for hit in hits {
                let s = hit.ayahRef.surah
                let a = hit.ayahRef.ayah
                let id = "at-\(s)-\(a)"
                if !results.contains(where: { $0.id == id }) {
                    let label = "\(metadata.surahName(s)) \(s):\(a)"
                    results.append(.ayahText(
                        surah: s, ayah: a,
                        label: label, hit: hit
                    ))
                }
            }
        }

        return results
    }

    /// Extracts a trailing number after the surah name, e.g. "yunus 10" → 10, else 1.
    private func parseTrailingAyah(_ text: String, surahName: String) -> Int {
        let lower = text.lowercased()
        let nameLower = surahName.lowercased()
        // Try stripping the surah name to find a trailing number
        let afterName: String
        if lower.hasPrefix(nameLower) {
            afterName = String(lower.dropFirst(nameLower.count))
        } else {
            // Try without "al-" prefix
            let strippedName = nameLower.hasPrefix("al-") ? String(nameLower.dropFirst(3)) : nameLower
            let strippedLower = lower.hasPrefix("al-") ? String(lower.dropFirst(3)) : lower
            if strippedLower.hasPrefix(strippedName) {
                afterName = String(strippedLower.dropFirst(strippedName.count))
            } else {
                return 1
            }
        }
        let trimmed = afterName.trimmingCharacters(in: .whitespaces)
        return Int(trimmed) ?? 1
    }

    private var searchResultsList: some View {
        List(searchResults) { result in
            Button {
                switch result {
                case .surahAyah(let s, let a, _):
                    recordAndJump(surah: s, ayah: a)
                case .ayahText(let s, let a, _, _):
                    recordRecentSearch(searchText)
                    recordAndJump(surah: s, ayah: a)
                case .page(let p):
                    recordAndJumpToPage(p)
                case .juz(_, let startPage):
                    recordAndJumpToPage(startPage)
                }
            } label: {
                switch result {
                case .surahAyah(_, _, let label):
                    Label(label, systemImage: "book")
                case .ayahText(_, _, let label, let hit):
                    VStack(alignment: .leading) {
                        Label(label, systemImage: "text.magnifyingglass")
                        (Text(hit.before).foregroundStyle(.secondary)
                         + Text(hit.match).bold()
                         + Text(hit.after).foregroundStyle(.secondary))
                            .font(.caption)
                            .lineLimit(1)
                            .environment(\.layoutDirection, .rightToLeft)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity)
                case .page(let p):
                    Label("Page \(p)", systemImage: "doc")
                case .juz(let j, _):
                    Label("Juz \(j)", systemImage: "books.vertical")
                }
            }
        }
        .listStyle(.plain)
    }

    private var recentSearchesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Searches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { clearRecentSearches() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentSearches, id: \.self) { query in
                        Button {
                            searchText = query
                        } label: {
                            Text(query)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.regularMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Recents Tab

    /// A unified recent entry combining jump history and listening sessions.
    private struct RecentEntry: Identifiable {
        enum Kind { case jump, listening }
        let id = UUID()
        let kind: Kind
        let surah: Int
        let ayah: Int
        let page: Int
        let date: Date
    }

    private var recentEntries: [RecentEntry] {
        var entries: [RecentEntry] = []
        var seen: Set<String> = [] // "surah:ayah" dedup key

        // Merge both sources sorted by date, keeping only the most recent per ayah
        var allRaw: [(kind: RecentEntry.Kind, surah: Int, ayah: Int, page: Int, date: Date)] = []

        for jump in jumpHistory.prefix(20) {
            let ref = jump.safeAyahRef
            allRaw.append((.jump, ref.surah, ref.ayah, jump.safePage, jump.timestamp ?? .distantPast))
        }
        for session in sessions.prefix(20) {
            let ref = session.safeAyahRef
            allRaw.append((.listening, ref.surah, ref.ayah, session.safePage, session.lastUpdated ?? .distantPast))
        }

        allRaw.sort { $0.date > $1.date }

        for raw in allRaw {
            let key = "\(raw.surah):\(raw.ayah)"
            guard seen.insert(key).inserted else { continue }
            entries.append(RecentEntry(
                kind: raw.kind,
                surah: raw.surah, ayah: raw.ayah,
                page: raw.page, date: raw.date
            ))
            if entries.count >= 15 { break }
        }

        return entries
    }

    private var recentsList: some View {
        Group {
            let entries = recentEntries
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Recents",
                    systemImage: "clock",
                    description: Text("Your jump and listening history will appear here.")
                )
            } else {
                List(entries) { entry in
                    Button {
                        recordAndJump(surah: entry.surah, ayah: entry.ayah)
                    } label: {
                        HStack {
                            Image(systemName: entry.kind == .listening ? "headphones" : "arrow.right.doc.on.clipboard")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading) {
                                Text("\(metadata.surahName(entry.surah)) \(entry.surah):\(entry.ayah)")
                                    .font(.subheadline)
                                Text(entry.date, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("p. \(entry.page)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}
