import SwiftUI

struct RecordingRowView: View {

    let recording: Recording
    var onTag: () -> Void

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
