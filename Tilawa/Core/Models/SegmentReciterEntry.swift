import SwiftData
import Foundation

@Model
final class SegmentReciterEntry {
    var id: UUID?
    var order: Int?        // 0 = highest priority
    var reciterId: UUID?   // references Reciter.id
    var isEnabled: Bool?

    @Relationship(inverse: \ReciterSegmentOverride.reciterPriority)
    var segmentOverride: ReciterSegmentOverride?

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.order = nil
        self.reciterId = nil
        self.isEnabled = nil
        self.segmentOverride = nil
    }

    // MARK: - Convenience initializer
    convenience init(order: Int, reciterId: UUID) {
        self.init()
        self.id = UUID()
        self.order = order
        self.reciterId = reciterId
        self.isEnabled = true
    }
}
