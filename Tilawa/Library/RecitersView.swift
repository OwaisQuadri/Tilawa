import SwiftUI
import SwiftData

/// Reciters tab — browse, download, and manage reciter priority.
struct RecitersView: View {

    @Query private var allReciters: [Reciter]
    @State private var isShowingManifestSheet = false

    private let dm = DownloadManager.shared

    private var allKnownReciters: [Reciter] {
        allReciters
            .filter { $0.hasCDN || $0.hasPersonalRecordings }
            .sorted { $0.safeName < $1.safeName }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allKnownReciters.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(allKnownReciters, id: \.id) { reciter in
                            NavigationLink {
                                ReciterDetailView(reciter: reciter)
                            } label: {
                                reciterRow(reciter)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Reciters")
            .toolbar { toolbarContent }
            .sheet(isPresented: $isShowingManifestSheet) {
                ManifestImportView()
            }
        }
    }

    // MARK: - Reciter row

    @ViewBuilder
    private func reciterRow(_ reciter: Reciter) -> some View {
        let cached = reciter.downloadedSurahs.count
        let activeJob = dm.activeJob(for: reciter.id ?? UUID())

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(reciter.safeName)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(reciter.riwayahSummaryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Group {
                        if reciter.hasCDN {
                            Label("CDN", systemImage: "icloud")
                                .font(.caption2)
                        }
                        if reciter.hasPersonalRecordings {
                            Label("Personal", systemImage: "waveform.badge.mic")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
                }
                if reciter.hasCDN {
                    if let job = activeJob {
                        ProgressView(value: job.overall)
                            .controlSize(.mini)
                        Text(job.statusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        coverageBadge(cached: cached)
                    }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func coverageBadge(cached: Int) -> some View {
        if cached == 0 {
            Text("No surahs downloaded")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if cached == 114 {
            Label("Complete", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Text("\(cached)/114 surahs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Reciters Yet", systemImage: "person.wave.2")
        } description: {
            Text("Download a CDN reciter or import personal recordings in the Library tab.")
        } actions: {
            Button {
                isShowingManifestSheet = true
            } label: {
                Label("Download CDN Reciter", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack {
                NavigationLink {
                    ReciterPriorityView()
                } label: {
                    Label("Priority", systemImage: "arrow.up.arrow.down")
                }
                Button {
                    isShowingManifestSheet = true
                } label: {
                    Label("Download CDN Reciter", systemImage: "arrow.down.circle")
                }
            }
        }
    }
}
