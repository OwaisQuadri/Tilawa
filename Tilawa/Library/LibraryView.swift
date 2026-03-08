import SwiftUI
import SwiftData

/// Library tab — manage imported audio recordings.
struct LibraryView: View {

    @State private var vm = LibraryViewModel()
    @State private var showingRecordingSession = false
    @Environment(\.modelContext) private var context

    @Query(sort: \Recording.importedAt, order: .reverse)
    private var recordings: [Recording]

    var body: some View {
        NavigationStack {
            List {
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
            // Video file picker (Photos library)
            .sheet(isPresented: $vm.isShowingVideoPicker) {
                VideoPhotoPickerView { urls in
                    Task { await vm.importVideoFile(urls: urls, context: context) }
                }
            }
            // YouTube import
            .sheet(isPresented: $vm.isShowingYouTubeImport) {
                YouTubeImportView(vm: vm)
            }
            // Generic URL import
            .sheet(isPresented: $vm.isShowingURLImport) {
                URLImportView(vm: vm)
            }
            // Inline annotation editor
            .sheet(item: $vm.pendingAnnotationRecording) { recording in
                AnnotationEditorView(recording: recording)
            }
            // In-app recording
            .fullScreenCover(isPresented: $showingRecordingSession) {
                RecordingSessionView()
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
                    let label: String = {
                        if let p = vm.importProgress {
                            return "Importing \(p.current) of \(p.total)…"
                        }
                        return "Importing…"
                    }()
                    ProgressView(label)
                        .padding(20)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Recordings section

    private var hasActiveYouTubeDownload: Bool {
        vm.pendingYouTubeImports.contains {
            if case .downloading = $0.state { return true }
            return false
        }
    }

    private var hasActiveURLDownload: Bool {
        vm.pendingURLImports.contains {
            if case .downloading = $0.state { return true }
            return false
        }
    }

    @ViewBuilder
    private var recordingSection: some View {
        let hasContent = !recordings.isEmpty || !vm.pendingYouTubeImports.isEmpty || !vm.pendingURLImports.isEmpty

        if !hasContent {
            Section {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init())
            }
        } else {
            // Pending / failed YouTube imports — shown in their own section so the
            // footer note is scoped only to this block and only while downloading.
            if !vm.pendingYouTubeImports.isEmpty {
                Section {
                    ForEach(vm.pendingYouTubeImports) { task in
                        YouTubeImportRowView(
                            task: task,
                            onStop: { vm.removePendingYouTubeImport(task) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if case .failed = task.state {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    vm.removePendingYouTubeImport(task)
                                }
                            }
                        }
                    }
                } footer: {
                    if hasActiveYouTubeDownload {
                        Label(
                            "Keep the app open while downloading from YouTube — the download will pause if you switch away. Audio and video file imports can finish briefly in the background.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                    }
                }
            }

            if !vm.pendingURLImports.isEmpty {
                Section {
                    ForEach(vm.pendingURLImports) { task in
                        URLImportRowView(
                            task: task,
                            onStop: { vm.removePendingURLImport(task) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if case .failed = task.state {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    vm.removePendingURLImport(task)
                                }
                            }
                        }
                    }
                } footer: {
                    if hasActiveURLDownload {
                        Label(
                            "Keep the app open while downloading — the download will pause if you switch away.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                    }
                }
            }

            if !recordings.isEmpty {
                Section {
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
                } header: {
                    HStack {
                        Text("Recordings")
                        Spacer()
                        Text(totalRecordingSizeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var totalRecordingSizeLabel: String {
        let total = recordings.compactMap(\.fileSizeBytes).reduce(0, +)
        guard total > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(total))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Recordings Yet", systemImage: "waveform")
        } description: {
            Text("Record audio, import files, or extract audio from a video.")
        } actions: {
            Menu("Import") {
                importMenuItems
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu("Import", systemImage: "plus") {
                importMenuItems
            }
        }
    }

    @ViewBuilder
    private var importMenuItems: some View {
        Button {
            showingRecordingSession = true
        } label: {
            Label("Record Audio", systemImage: "mic.fill")
        }

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

        Button {
            vm.isShowingYouTubeImport = true
        } label: {
            Label("Import from YouTube", systemImage: "play.rectangle.fill")
        }

        Button {
            vm.isShowingURLImport = true
        } label: {
            Label("Import from URL", systemImage: "link")
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
