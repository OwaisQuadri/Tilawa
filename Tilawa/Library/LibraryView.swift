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
                    ProgressView("Importing…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Recordings section

    @ViewBuilder
    private var recordingSection: some View {
        if recordings.isEmpty {
            Section {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init())
            }
        } else {
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
