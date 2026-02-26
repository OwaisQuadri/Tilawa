import SwiftUI
import SwiftData

/// Main Library tab. Lists user recordings, CDN reciters with coverage,
/// and provides import options, annotation editor, and priority management.
struct LibraryView: View {

    @State private var vm = LibraryViewModel()
    @Environment(\.modelContext) private var context

    @Query(sort: \Recording.importedAt, order: .reverse)
    private var recordings: [Recording]

    @Query private var allReciters: [Reciter]

    private var allKnownReciters: [Reciter] {
        allReciters
            .filter { $0.hasCDN || $0.hasPersonalRecordings }
            .sorted { $0.safeName < $1.safeName }
    }

    private let dm = DownloadManager.shared

    var body: some View {
        NavigationStack {
            List {
                reciterSection
                recordingSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .toolbar { toolbarContent }
            // Audio file picker
            .sheet(isPresented: $vm.isShowingAudioPicker) {
                DocumentPickerView(types: AudioImporter.supportedAudioTypes) { urls in
                    Task { await vm.importAudioFile(urls: urls, context: context) }
                }
            }
            // Video file picker
            .sheet(isPresented: $vm.isShowingVideoPicker) {
                DocumentPickerView(types: AudioImporter.supportedVideoTypes) { urls in
                    Task { await vm.importVideoFile(urls: urls, context: context) }
                }
            }
            // CDN manifest importer
            .sheet(isPresented: $vm.isShowingManifestSheet) {
                ManifestImportView()
            }
            // Inline annotation editor
            .sheet(item: $vm.pendingAnnotationRecording) { recording in
                AnnotationEditorView(recording: recording)
            }
            // Import error
            .alert("Import Failed", isPresented: .constant(vm.importError != nil)) {
                Button("OK") { vm.importError = nil }
            } message: {
                Text(vm.importError ?? "")
            }
            // Importing overlay
            .overlay {
                if vm.isImporting {
                    ProgressView("Importing…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Reciters section

    @ViewBuilder
    private var reciterSection: some View {
        if !allKnownReciters.isEmpty {
            Section {
                ForEach(allKnownReciters, id: \.id) { reciter in
                    NavigationLink {
                        ReciterDetailView(reciter: reciter)
                    } label: {
                        reciterRow(reciter)
                    }
                }
            } header: {
                HStack {
                    Text("Reciters")
                    Spacer()
                    NavigationLink {
                        ReciterPriorityView()
                    } label: {
                        Label("Priority", systemImage: "arrow.up.arrow.down")
                            .font(.caption)
                            .textCase(nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func reciterRow(_ reciter: Reciter) -> some View {
        let cached = reciter.downloadedSurahs.count
        let activeJob = dm.activeJob(for: reciter.id ?? UUID())

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(reciter.safeName)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(reciter.safeRiwayah.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let style = reciter.style, !style.isEmpty {
                        Text("· \(style.capitalized)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                // Coverage / active progress (only for CDN reciters)
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

    // MARK: - Recordings section

    @ViewBuilder
    private var recordingSection: some View {
        if recordings.isEmpty && allKnownReciters.isEmpty {
            Section {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init())
            }
        } else if !recordings.isEmpty {
            Section("Recordings") {
                ForEach(recordings, id: \.id) { recording in
                    NavigationLink {
                        RecordingDetailView(recording: recording)
                    } label: {
                        RecordingRowView(recording: recording) {
                            vm.pendingAnnotationRecording = recording
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Tag", systemImage: "tag") {
                            vm.pendingAnnotationRecording = recording
                        }
                        .tint(.accentColor)
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deleteRecording(recording)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing Here Yet", systemImage: "waveform")
        } description: {
            Text("Import audio files, extract audio from video, or download a CDN reciter.")
        } actions: {
            Menu("Add") {
                importMenuItems
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu("Add", systemImage: "plus") {
                importMenuItems
            }
        }
    }

    @ViewBuilder
    private var importMenuItems: some View {
        Button {
            vm.isShowingAudioPicker = true
        } label: {
            Label("Import Audio File", systemImage: "doc.badge.plus")
        }

        Button {
            vm.isShowingVideoPicker = true
        } label: {
            Label("Import Video File", systemImage: "film")
        }

        Divider()

        Button {
            vm.isShowingManifestSheet = true
        } label: {
            Label("Download CDN Reciter", systemImage: "arrow.down.circle")
        }
    }

    // MARK: - Delete

    private func deleteRecording(_ recording: Recording) {
        if let path = recording.storagePath {
            let url = AudioImporter.recordingsDirectory.appendingPathComponent(path)
            try? FileManager.default.removeItem(at: url)
        }
        context.delete(recording)
        try? context.save()
    }
}
