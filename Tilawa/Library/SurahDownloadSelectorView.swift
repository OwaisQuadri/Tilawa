import SwiftUI
import SwiftData

/// Lets the user select which surahs to cache locally for a CDN reciter.
/// Downloads run in parallel via DownloadManager and continue if the view is dismissed.
struct SurahDownloadSelectorView: View {

    let reciter: Reciter
    var dismissSheet: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSurahs: Set<Int> = []
    @State private var cachedSurahs: Set<Int> = []
    @State private var currentJobId: UUID?
    @State private var showBackgroundAlert = false
    @State private var showCompletionAlert = false
    @State private var completionMessage = ""

    private let metadata = QuranMetadataService.shared
    private let dm = DownloadManager.shared

    // MARK: - Derived state

    private var activeJob: DownloadManager.DownloadJob? {
        currentJobId.flatMap { dm.jobs[$0] }
    }

    private var isDownloading: Bool { activeJob != nil }

    /// Watches the active job's isDone state (nil when no job or job removed).
    private var currentJobDone: Bool? {
        activeJob?.isDone
    }

    // MARK: - Body

    var body: some View {
        List {
            // Active download progress banner
            if let job = activeJob {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: job.overall)
                        HStack {
                            Text(job.statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.0f%%", job.overall * 100))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Select-all toggle (only uncached)
            Section {
                Toggle("Select All Uncached", isOn: allUncachedSelected)
                    .disabled(isDownloading)
            }

            Section("Surahs") {
                ForEach(1...114, id: \.self) { surah in
                    surahRow(surah: surah)
                }
            }
        }
        .navigationTitle("Download Surahs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isDownloading {
                    Button("Dismiss") { dismissFully() }
                } else {
                    Button("Download") { startDownload() }
                        .disabled(selectedSurahs.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
        // "Downloads started — you can leave" alert
        .alert("Downloads Started", isPresented: $showBackgroundAlert) {
            Button("Stay") {}
            Button("Dismiss") { dismissFully() }
        } message: {
            Text("Downloading \(selectedSurahs.count) surah\(selectedSurahs.count == 1 ? "" : "s") for \(reciter.safeName). Downloads continue in the background and you'll get a notification when done.")
        }
        // Completion alert (fires if view is still open)
        .alert("Download Complete", isPresented: $showCompletionAlert) {
            Button("OK") { dismissFully() }
        } message: {
            Text(completionMessage)
        }
        .task { await loadCachedSurahs() }
        .onChange(of: currentJobDone) { _, isDone in
            guard isDone == true, let jobId = currentJobId,
                  let job = dm.jobs[jobId] else { return }
            completionMessage = job.failedSurahs.isEmpty
                ? "\(job.completedCount) surah\(job.completedCount == 1 ? "" : "s") downloaded successfully."
                : "\(job.completedCount) downloaded, \(job.failedSurahs.count) failed."
            showCompletionAlert = true
        }
    }

    // MARK: - Surah row

    @ViewBuilder
    private func surahRow(surah: Int) -> some View {
        let isCached = cachedSurahs.contains(surah)
        let jobProgress = activeJob?.surahProgress[surah]

        HStack {
            Toggle(isOn: surahToggle(surah)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.surahName(surah))
                        .font(.body)
                        .foregroundStyle(isCached ? .secondary : .primary)
                    HStack(spacing: 4) {
                        Text("\(metadata.ayahCount(surah: surah)) ayaat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isCached {
                            Text("· Cached")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .disabled(isDownloading)

            Spacer()

            // Per-surah progress/status
            if let p = jobProgress {
                if p >= 1.0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if p == 0 && activeJob?.failedSurahs.contains(surah) == true {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                } else {
                    ProgressView(value: p)
                        .frame(width: 44)
                        .controlSize(.small)
                }
            } else if isCached && !isDownloading {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Controls

    private var allUncachedSelected: Binding<Bool> {
        Binding(
            get: {
                let uncached = Set(1...114).subtracting(cachedSurahs)
                return !uncached.isEmpty && selectedSurahs.isSuperset(of: uncached)
            },
            set: { all in
                if all {
                    selectedSurahs = Set(1...114).subtracting(cachedSurahs)
                } else {
                    selectedSurahs = []
                }
            }
        )
    }

    private func surahToggle(_ surah: Int) -> Binding<Bool> {
        Binding(
            get: { selectedSurahs.contains(surah) },
            set: { on in
                if on { selectedSurahs.insert(surah) }
                else  { selectedSurahs.remove(surah) }
            }
        )
    }

    // MARK: - Actions

    /// Dismisses the entire import sheet (back to Library), falling back to a single pop.
    private func dismissFully() {
        if let dismissSheet { dismissSheet() } else { dismiss() }
    }

    private func startDownload() {
        let jobId = dm.enqueue(
            surahs: Array(selectedSurahs).sorted(),
            reciter: reciter,
            context: context
        )
        currentJobId = jobId
        showBackgroundAlert = true
    }

    private func loadCachedSurahs() async {
        // Seed from model (fast), then optionally verify from disk
        let modelCached = Set(reciter.downloadedSurahs)
        cachedSurahs = modelCached

        // Also pre-select all uncached surahs by default
        selectedSurahs = Set(1...114).subtracting(cachedSurahs)
    }
}
