import Foundation
import SwiftData

@Model
final class JumpHistory {
    var surah: Int?
    var ayah: Int?
    var page: Int?
    var timestamp: Date?

    init(surah: Int, ayah: Int, page: Int) {
        self.surah = surah
        self.ayah = ayah
        self.page = page
        self.timestamp = Date()
    }

    var safeAyahRef: AyahRef {
        AyahRef(surah: surah ?? 1, ayah: ayah ?? 1)
    }

    var safePage: Int { page ?? 1 }
}
