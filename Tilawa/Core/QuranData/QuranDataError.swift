import Foundation

enum QuranDataError: LocalizedError {
    case pageNotFound(Int)
    case metadataLoadFailed
    case surahNotFound(Int)
    case invalidAyahRef(surah: Int, ayah: Int)

    var errorDescription: String? {
        switch self {
        case .pageNotFound(let page):
            "Page \(page) not found in bundle"
        case .metadataLoadFailed:
            "Failed to load Quran metadata from bundle"
        case .surahNotFound(let surah):
            "Surah \(surah) not found"
        case .invalidAyahRef(let surah, let ayah):
            "Invalid ayah reference: \(surah):\(ayah)"
        }
    }
}
