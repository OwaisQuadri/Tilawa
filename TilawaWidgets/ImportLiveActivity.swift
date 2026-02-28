import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Shared Attributes (duplicated from Tilawa/Library/ImportActivityAttributes.swift)
// Both targets must define this struct identically for ActivityKit serialisation to work.

struct ImportActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var filesCompleted: Int
        var filesTotal: Int
        var currentFileName: String
    }
}

// MARK: - Live Activity Widget

struct ImportLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ImportActivityAttributes.self) { context in
            // Lock Screen / Notification Center view
            ImportLockScreenView(state: context.state)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.primary)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Label("Importing", systemImage: "doc.badge.plus")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.filesCompleted) / \(context.state.filesTotal)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.currentFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } compactLeading: {
                Image(systemName: "doc.badge.plus")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text("\(context.state.filesCompleted)/\(context.state.filesTotal)")
                    .font(.caption.monospacedDigit())
            } minimal: {
                Image(systemName: "doc.badge.plus")
                    .foregroundStyle(.blue)
            }
            .widgetURL(URL(string: "tilawa://library"))
            .keylineTint(.blue)
        }
    }
}

// MARK: - Lock Screen View

private struct ImportLockScreenView: View {
    let state: ImportActivityAttributes.ContentState

    private var progress: Double {
        guard state.filesTotal > 0 else { return 0 }
        return Double(state.filesCompleted) / Double(state.filesTotal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, isActive: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Importing \(state.filesCompleted) of \(state.filesTotal)")
                        .font(.subheadline.bold())
                    Text(state.currentFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text("Tilawa")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ProgressView(value: progress)
                .tint(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
