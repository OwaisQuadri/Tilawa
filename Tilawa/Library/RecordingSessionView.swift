import SwiftUI
import SwiftData

/// Full-screen modal for recording audio directly via the microphone.
struct RecordingSessionView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var vm = MicrophoneRecorderViewModel()
    @State private var recordingTitle = ""
    @State private var showingDiscardConfirm = false
    @State private var showingNamePrompt = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                levelMeter
                    .padding(.horizontal, 24)
                    .frame(height: 80)
                Spacer()
                elapsedDisplay
                Spacer()
                recordButton
                pauseButton
                Spacer()
                bottomActions
                    .padding(.bottom, 20)
            }
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { cancelButton }
            .onAppear { vm.requestPermission() }
            .alert("Recording Error", isPresented: .constant(vm.saveError != nil)) {
                Button("OK") { vm.saveError = nil }
            } message: {
                Text(vm.saveError ?? "")
            }
            .alert("Discard Recording?", isPresented: $showingDiscardConfirm) {
                Button("Discard", role: .destructive) { vm.discard(); dismiss() }
                Button("Keep Recording", role: .cancel) { }
            } message: {
                Text("The recording will be permanently deleted.")
            }
            .alert("Name Your Recording", isPresented: $showingNamePrompt) {
                TextField("Recording name", text: $recordingTitle)
                    .autocorrectionDisabled()
                Button("Save") { commitSave() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Give this recording a name, or leave it blank for a default name.")
            }
        }
    }

    // MARK: - Level Meter

    private var levelMeter: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(vm.levelSamples.enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: level))
                        .frame(width: max(2, (geo.size.width - CGFloat(vm.levelSamples.count) * 2) / CGFloat(vm.levelSamples.count)),
                               height: max(4, geo.size.height * CGFloat(level)))
                        .animation(.linear(duration: 0.05), value: level)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func barColor(for level: Float) -> Color {
        switch level {
        case 0..<0.6: return .accentColor
        case 0.6..<0.85: return .yellow
        default: return .red
        }
    }

    // MARK: - Elapsed Timer Display

    private var elapsedDisplay: some View {
        Text(vm.elapsedLabel)
            .font(.system(size: 56, weight: .thin, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(vm.state == .recording ? .primary : .secondary)
            .contentTransition(.numericText())
            .animation(.default, value: vm.elapsedLabel)
    }

    // MARK: - Record / Stop Button

    private var recordButton: some View {
        Button {
            switch vm.state {
            case .ready, .paused:
                vm.startRecording()
            case .recording:
                vm.stopRecording()
                showingNamePrompt = true
            default:
                break
            }
        } label: {
            ZStack {
                Circle()
                    .fill(buttonFill)
                    .frame(width: 80, height: 80)
                    .shadow(color: .red.opacity(vm.state == .recording ? 0.4 : 0), radius: 12)

                if vm.state == .recording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white)
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 36, height: 36)
                }
            }
        }
        .disabled(vm.state == .idle || vm.state == .permissionDenied || vm.state == .saved)
        .animation(.spring(response: 0.3), value: vm.state)
    }

    private var buttonFill: Color {
        switch vm.state {
        case .recording: return .red
        case .paused: return .orange
        default: return .red.opacity(0.8)
        }
    }

    // MARK: - Pause Button

    @ViewBuilder
    private var pauseButton: some View {
        if vm.state == .recording || vm.state == .paused {
            Button {
                if vm.state == .recording {
                    vm.pauseRecording()
                } else {
                    vm.startRecording() // resume
                }
            } label: {
                Label(vm.state == .recording ? "Pause" : "Resume",
                      systemImage: vm.state == .recording ? "pause.fill" : "play.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .padding(.top, 16)
        } else {
            Color.clear.frame(height: 44 + 16) // reserve space
        }
    }

    // MARK: - Permission Denied Banner

    // MARK: - Bottom Actions

    @ViewBuilder
    private var bottomActions: some View {
        switch vm.state {
        case .permissionDenied:
            VStack(spacing: 8) {
                Label("Microphone access is required.", systemImage: "mic.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        case .recording, .paused:
            Button(role: .destructive) {
                showingDiscardConfirm = true
            } label: {
                Label("Discard", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        default:
            EmptyView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var cancelButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if vm.state == .recording || vm.state == .paused {
                    showingDiscardConfirm = true
                } else {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Save

    private func commitSave() {
        do {
            try vm.save(title: recordingTitle, context: context)
            dismiss()
        } catch {
            vm.saveError = error.localizedDescription
        }
    }
}
