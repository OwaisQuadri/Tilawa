import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Shared Attributes (duplicated from Tilawa/Library/RecordingActivityAttributes.swift)
// Both targets must define this struct identically for ActivityKit serialisation to work.

struct RecordingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var isPaused: Bool
    }
    var startDate: Date
}

// MARK: - Live Activity Widget

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock Screen / Notification Center view
            LockScreenView(state: context.state, startDate: context.attributes.startDate)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.primary)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Label("Recording", systemImage: context.state.isPaused ? "pause.circle.fill" : "mic.fill")
                        .font(.headline)
                        .foregroundStyle(context.state.isPaused ? .orange : .red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(elapsedText(context.state.elapsedSeconds))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.isPaused ? "Paused — open Tilawa to resume" : "Recording in progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "mic.fill")
                    .foregroundStyle(context.state.isPaused ? .orange : .red)
            } compactTrailing: {
                Text(elapsedText(context.state.elapsedSeconds))
                    .font(.caption.monospacedDigit())
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            }
            .widgetURL(URL(string: "tilawa://recording"))
            .keylineTint(.red)
        }
    }

    private func elapsedText(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let state: RecordingActivityAttributes.ContentState
    let startDate: Date

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: state.isPaused ? "pause.circle.fill" : "mic.fill")
                .font(.title2)
                .foregroundStyle(state.isPaused ? .orange : .red)
                .symbolEffect(.pulse, isActive: !state.isPaused)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.isPaused ? "Recording Paused" : "Recording")
                    .font(.subheadline.bold())
                Text(elapsedText(state.elapsedSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Tilawa")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func elapsedText(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
