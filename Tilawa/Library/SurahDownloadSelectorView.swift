import SwiftUI
import SwiftData

/// Shows all surahs available on a CDN source with per-surah download/cached status.
/// A single "Download All" action downloads everything not yet cached.
struct SurahDownloadSelectorView: View {

    let reciter: Reciter
    var source: ReciterCDNSource? = nil
    var dismissSheet: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var cachedSurahs: Set<Int> = []
    /// Per-surah availability: surah → (available, total)
    @State private var surahAvailability: [Int: (available: Int, total: Int)] = [:]
    @State private var currentJobId: UUID?
    @State private var isCheckingAvailability = false
    @State private var availabilityProgress: Double = 0
    @State private var showClearCacheConfirmation = false

    private let metadata = QuranMetadataService.shared
    private let dm = DownloadManager.shared

    // MARK: - Derived state

    private var activeJob: DownloadManager.DownloadJob? {
        // Prefer locally-started job, fall back to any running job for this source
        if let id = currentJobId, let job = dm.jobs[id] { return job }
        guard let reciterId = reciter.id else { return nil }
        let resolvedSource = source ?? reciter.cdnSources?.first
        if let sourceId = resolvedSource?.id {
            return dm.activeJob(for: reciterId, sourceId: sourceId)
        }
        return dm.activeJob(for: reciterId)
    }

    private var isDownloading: Bool { activeJob != nil }

    /// Surahs that have at least one available ayah on the CDN.
    private var availableSurahs: [Int] {
        surahAvailability
            .filter { $0.value.available > 0 }
            .keys.sorted()
    }

    /// Surahs available but not fully cached yet.
    private var uncachedSurahs: [Int] {
        availableSurahs.filter { !cachedSurahs.contains($0) }
    }

    /// Shareable CDN config string (URL template, base URL, or manifest URL).
    private var shareable: String? {
        let resolved = source ?? reciter.cdnSources?.first
        if let template = resolved?.urlTemplate { return template }
        if let base = resolved?.baseURL { return base }
        return nil
    }

    // MARK: - Body

    var body: some View {
        List {
            if isCheckingAvailability {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Checking CDN availability...", systemImage: "network")
                            .font(.subheadline)
                        ProgressView(value: availabilityProgress)
                        Text("\(Int(availabilityProgress * 6236))/6236 ayaat checked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }

            if !isCheckingAvailability {
                // Summary
                if !surahAvailability.isEmpty {
                    let totalAvailable = surahAvailability.values.reduce(0) { $0 + $1.available }
                    let totalAyahs = surahAvailability.values.reduce(0) { $0 + $1.total }
                    let unavailableCount = surahAvailability.values.filter { $0.available == 0 }.count
                    Section {
                        if unavailableCount > 0 {
                            Label("\(availableSurahs.count) surahs available (\(totalAvailable)/\(totalAyahs) ayaat). \(unavailableCount) unavailable — hidden.",
                                  systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("All \(totalAvailable) ayaat available across \(availableSurahs.count) surahs.",
                                  systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                if availableSurahs.isEmpty && !surahAvailability.isEmpty {
                    Section {
                        Label("No ayaat are available on this CDN.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Section("Surahs") {
                        ForEach(availableSurahs, id: \.self) { surah in
                            surahRow(surah: surah)
                        }
                    }
                }
            }
        }
        .navigationTitle("Manage CDN")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if !cachedSurahs.isEmpty {
                        Button(role: .destructive) {
                            showClearCacheConfirmation = true
                        } label: {
                            Label("Clear Cache", systemImage: "trash")
                        }
                    } else {
                        Button {
                            startDownload()
                        } label: {
                            Label("Download All", systemImage: "tray.and.arrow.down")
                        }
                        .disabled(uncachedSurahs.isEmpty || isDownloading || isCheckingAvailability)
                    }
                    if let shareText = shareable {
                        ShareLink(item: shareText) {
                            Label("Share CDN", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        guard let resolvedSource = source ?? reciter.cdnSources?.first else { return }
                        Task { await runAvailabilityCheck(source: resolvedSource) }
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.clockwise")
                    }
                    .disabled(isCheckingAvailability || isDownloading)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Clear Cache?", isPresented: $showClearCacheConfirmation) {
            Button("Clear Cached Audio", role: .destructive) {
                guard let resolvedSource = source ?? reciter.cdnSources?.first else { return }
                Task {
                    await AudioFileCache.shared.deleteCache(for: reciter, source: resolvedSource)
                    cachedSurahs = []
                }
            }
        } message: {
            Text("This will delete cached audio for this CDN source. Files can be re-downloaded.")
        }
        .task { await loadState() }
    }

    // MARK: - Surah row

    @ViewBuilder
    private func surahRow(surah: Int) -> some View {
        let isCached = cachedSurahs.contains(surah)
        let availability = surahAvailability[surah]
        let available = availability?.available ?? 0
        let total = availability?.total ?? metadata.ayahCount(surah: surah)
        let isPartial = available < total
        let jobProgress = activeJob?.surahProgress[surah]
        let failed = activeJob?.failedSurahs.contains(surah) == true

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(metadata.surahName(surah))
                    .font(.body)
                    .foregroundStyle(isCached ? .secondary : .primary)
                Spacer()
                if isPartial {
                    Text("\(available)/\(total) ayaat")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("\(total) ayaat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isCached || jobProgress.map({ $0 >= 1.0 }) == true {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if failed {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            if let p = jobProgress, p < 1.0, !failed {
                ProgressView(value: p)
                    .controlSize(.mini)
            }
        }
    }

    // MARK: - Actions

    private func dismissFully() {
        if let dismissSheet { dismissSheet() } else { dismiss() }
    }

    private func startDownload() {
        let jobId = dm.enqueue(
            surahs: uncachedSurahs,
            reciter: reciter,
            source: source,
            context: context
        )
        currentJobId = jobId
    }

    private func loadState() async {
        guard let resolvedSource = source ?? reciter.cdnSources?.first else { return }

        // Build availability from this source's missingAyahsJSON
        let missing = resolvedSource.missingAyahs
        let missingSet = Set(missing)

        let needsFreshCheck = !resolvedSource.availabilityChecked || missing.count == 6236

        if needsFreshCheck {
            await runAvailabilityCheck(source: resolvedSource)
        } else {
            buildAvailabilityFromMissing(missingSet)
        }

        // Check cache status after availability is known
        await refreshCachedSurahs(source: resolvedSource)
    }

    private func runAvailabilityCheck(source: ReciterCDNSource) async {
        isCheckingAvailability = true

        // Check for version change (content updates for same ayahs)
        let oldVersion = source.cdnVersion
        let remoteVersion = await fetchManifestVersion(for: source)
        let versionChanged = remoteVersion != nil && remoteVersion != oldVersion

        let missing = await CDNAvailabilityChecker.shared.findMissingAyahs(
            reciter: reciter,
            source: source,
            progress: { p in
                Task { @MainActor in
                    availabilityProgress = p
                }
            }
        )

        // Persist results on the specific source
        if let encoded = try? JSONEncoder().encode(missing),
           let json = String(data: encoded, encoding: .utf8) {
            source.missingAyahsJSON = json
        } else {
            source.missingAyahsJSON = "[]"
        }
        if let remoteVersion {
            source.cdnVersion = remoteVersion
        }
        try? context.save()

        // If version changed, clear stale cache so files are re-downloaded
        if versionChanged {
            await AudioFileCache.shared.deleteCache(for: reciter, source: source)
        }

        buildAvailabilityFromMissing(Set(missing))
        isCheckingAvailability = false
        await refreshCachedSurahs(source: source)
    }

    private func fetchManifestVersion(for source: ReciterCDNSource) async -> Int? {
        guard let folderId = source.cdnFolderId else { return nil }
        let urlString = "\(CDNUploadManager.workerBaseURL)/manifests/\(folderId).json"
        guard let url = URL(string: urlString) else { return nil }
        struct VersionResponse: Codable { let version: Int? }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(VersionResponse.self, from: data).version
        } catch {
            return nil
        }
    }

    private func buildAvailabilityFromMissing(_ missingSet: Set<AyahRef>) {
        var availability: [Int: (available: Int, total: Int)] = [:]
        for surah in 1...114 {
            let total = metadata.ayahCount(surah: surah)
            let missingInSurah = (1...max(1, total)).filter { ayah in
                missingSet.contains(AyahRef(surah: surah, ayah: ayah))
            }.count
            availability[surah] = (available: total - missingInSurah, total: total)
        }
        surahAvailability = availability
    }

    /// Marks a surah as cached if all *available* ayahs (not missing) are on disk.
    private func refreshCachedSurahs(source: ReciterCDNSource) async {
        let cache = AudioFileCache.shared
        let missingSet = Set(source.missingAyahs)
        var cached = Set<Int>()
        for surah in 1...114 {
            let total = metadata.ayahCount(surah: surah)
            guard total > 0 else { continue }
            let availableRefs = (1...total)
                .map { AyahRef(surah: surah, ayah: $0) }
                .filter { !missingSet.contains($0) }
            guard !availableRefs.isEmpty else { continue }
            let allCached = await availableRefs.asyncAllSatisfy {
                cache.isFileCached(ref: $0, reciter: reciter, source: source)
            }
            if allCached { cached.insert(surah) }
        }
        cachedSurahs = cached
    }
}

private extension Array {
    func asyncAllSatisfy(_ predicate: (Element) async -> Bool) async -> Bool {
        for element in self {
            if await !predicate(element) { return false }
        }
        return true
    }
}

