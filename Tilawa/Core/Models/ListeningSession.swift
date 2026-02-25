import Foundation
import SwiftData

@Model
final class ListeningSession {
    var lastSurah: Int?
    var lastAyah: Int?
    var lastPage: Int?
    var lastUpdated: Date?
    var totalListeningSeconds: Double?

    init(page: Int, surah: Int = 1, ayah: Int = 1) {
        self.lastPage = page
        self.lastSurah = surah
        self.lastAyah = ayah
        self.lastUpdated = Date()
        self.totalListeningSeconds = 0
    }

    /// Safe accessors.
    var safePage: Int { lastPage ?? 1 }
    var safeAyahRef: AyahRef {
        AyahRef(surah: lastSurah ?? 1, ayah: lastAyah ?? 1)
    }

    func updatePosition(page: Int, surah: Int, ayah: Int) {
        self.lastPage = page
        self.lastSurah = surah
        self.lastAyah = ayah
        self.lastUpdated = Date()
    }
}
