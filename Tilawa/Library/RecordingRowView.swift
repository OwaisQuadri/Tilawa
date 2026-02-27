import SwiftUI
import SwiftData

struct RecordingRowView: View {

    let recording: Recording
    var onTag: () -> Void

    @Environment(\.modelContext) private var context
    @State private var showingRename = false
    @State private var pendingName = ""

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.safeTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(durationLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    statusBadge

                    if recording.fileFormat != nil {
                        Text((recording.fileFormat ?? "").uppercased())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Button("Tag", action: onTag)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading) {
            Button("Rename", systemImage: "pencil") {
                pendingName = recording.safeTitle
                showingRename = true
            }
            .tint(.blue)
        }
        .alert("Rename Recording", isPresented: $showingRename) {
            TextField("Name", text: $pendingName)
                .autocorrectionDisabled()
            Button("Save") {
                recording.title = pendingName.isEmpty ? recording.title : pendingName
                try? context.save()
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var durationLabel: String {
        let secs = Int(recording.safeDuration)
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch recording.annotationStatusEnum {
        case .unannotated:
            Label("Untagged", systemImage: "tag.slash")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .partial:
            Label("Partial", systemImage: "tag")
                .font(.caption2)
                .foregroundStyle(.yellow)
        case .complete:
            Label("Tagged", systemImage: "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        }
    }
}
