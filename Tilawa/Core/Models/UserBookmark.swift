import Foundation
import SwiftData

@Model
final class UserBookmark {
    var surah: Int?
    var ayah: Int?
    var page: Int?
    var label: String?
    var color: String?
    var createdAt: Date?

    init(surah: Int, ayah: Int, page: Int, label: String = "", color: String = "blue") {
        self.surah = surah
        self.ayah = ayah
        self.page = page
        self.label = label
        self.color = color
        self.createdAt = Date()
    }

    /// Safe accessors hiding CloudKit optionality.
    var safeAyahRef: AyahRef {
        AyahRef(surah: surah ?? 1, ayah: ayah ?? 1)
    }

    var safePage: Int { page ?? 1 }
    var safeLabel: String { label ?? "" }
}
