import SwiftUI
import SwiftData

/// Reciters tab — browse, download, and manage reciter priority.
struct RecitersView: View {

    @Query private var allReciters: [Reciter]
    @State private var isShowingManifestSheet = false

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
            }
            Spacer()
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
