import ActivityKit
import Foundation

/// Shared ActivityKit attributes for the in-app microphone recording Live Activity.
/// NOTE: This struct must also exist in the TilawaWidgets target with the same definition.
/// See TilawaWidgets/RecordingLiveActivity.swift.
struct RecordingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var isPaused: Bool
    }
    /// The date recording started (used to derive elapsed time on the lock screen).
    var startDate: Date
}
