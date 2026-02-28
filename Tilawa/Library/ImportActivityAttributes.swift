import ActivityKit
import Foundation

/// Shared ActivityKit attributes for the bulk file import Live Activity.
/// NOTE: This struct must also exist in TilawaWidgets/ImportLiveActivity.swift with the same definition.
struct ImportActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var filesCompleted: Int
        var filesTotal: Int
        var currentFileName: String
    }
}
