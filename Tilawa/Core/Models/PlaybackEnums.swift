import Foundation

/// What happens after all range repetitions complete.
enum AfterRepeatAction: String, CaseIterable, Codable {
    case stop           = "stop"
    case continueAyaat  = "continueAyaat"
    case continuePages  = "continuePages"
}

/// Annotation progress for a UGC recording.
enum AnnotationStatus: String, Codable {
    case unannotated = "unannotated"
    case partial     = "partial"
    case complete    = "complete"
}

/// How a CDN reciter's audio files are named.
enum ReciterNamingPattern: String, Codable {
    /// Files named {surah3}{ayah3}.{format} — e.g. 001001.mp3 (EveryAyah format)
    case surahAyah  = "surah_ayah"
    /// Files named by sequential ayah index 1–6236 — e.g. 1.mp3 (Al Quran Cloud format)
    case sequential = "sequential"
}
