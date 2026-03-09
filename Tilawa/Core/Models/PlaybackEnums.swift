import Foundation

/// What happens after all range repetitions complete.
enum AfterRepeatAction: String, CaseIterable, Codable {
    case stop           = "stop"
    case continueAyaat  = "continueAyaat"
    case continuePages  = "continuePages"
}

/// Concrete picker options for after-repeat behavior.
/// Each case encodes both the action and its parameters.
enum AfterRepeatOption: Int, CaseIterable, Identifiable {
    case disabled       = 0
    case ayaat3         = 3
    case ayaat5         = 5
    case ayaat10        = 10
    case page           = -100
    case pageExtraAyah  = -101

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .disabled:      return "Disabled"
        case .ayaat3:        return "3 ayahs"
        case .ayaat5:        return "5 ayahs"
        case .ayaat10:       return "10 ayahs"
        case .page:          return "1 page"
        case .pageExtraAyah: return "1 page + 1 ayah"
        }
    }

    var shortLabel: String? {
        switch self {
        case .disabled:      return nil
        case .ayaat3:        return "3a"
        case .ayaat5:        return "5a"
        case .ayaat10:       return "10a"
        case .page:          return "1pg"
        case .pageExtraAyah: return "1pg + 1a"
        }
    }

    /// Reads the current option from PlaybackSettings.
    static func from(_ s: PlaybackSettings) -> AfterRepeatOption {
        switch s.safeAfterRepeatAction {
        case .stop:          return .disabled
        case .continueAyaat: return AfterRepeatOption(rawValue: s.afterRepeatContinueAyaatCount ?? 3) ?? .ayaat3
        case .continuePages: return (s.afterRepeatContinuePagesExtraAyah == true) ? .pageExtraAyah : .page
        }
    }

    /// Reads the current option from a PlaybackSettingsSnapshot.
    static func from(_ s: PlaybackSettingsSnapshot) -> AfterRepeatOption {
        switch s.afterRepeatAction {
        case .stop:          return .disabled
        case .continueAyaat: return AfterRepeatOption(rawValue: s.afterRepeatContinueAyaatCount) ?? .ayaat3
        case .continuePages: return s.afterRepeatContinuePagesExtraAyah ? .pageExtraAyah : .page
        }
    }

    /// Writes this option into PlaybackSettings.
    func apply(to s: PlaybackSettings) {
        switch self {
        case .disabled:
            s.afterRepeatAction = AfterRepeatAction.stop.rawValue
            s.afterRepeatContinuePagesExtraAyah = false
        case .ayaat3, .ayaat5, .ayaat10:
            s.afterRepeatAction = AfterRepeatAction.continueAyaat.rawValue
            s.afterRepeatContinueAyaatCount = rawValue
            s.afterRepeatContinuePagesExtraAyah = false
        case .page:
            s.afterRepeatAction = AfterRepeatAction.continuePages.rawValue
            s.afterRepeatContinuePagesCount = 1
            s.afterRepeatContinuePagesExtraAyah = false
        case .pageExtraAyah:
            s.afterRepeatAction = AfterRepeatAction.continuePages.rawValue
            s.afterRepeatContinuePagesCount = 1
            s.afterRepeatContinuePagesExtraAyah = true
        }
    }
}

/// Annotation progress for a UGC recording.
enum AnnotationStatus: String, Codable {
    case unannotated = "unannotated"
    case partial     = "partial"
    case complete    = "complete"
}

/// Whether ayah repeats apply to every range pass or only the first.
enum RangeRepeatBehavior: String, CaseIterable, Codable {
    case whileRepeatingAyahs = "whileRepeatingAyahs"   // default: every pass includes ayah repeats
    case afterRepeatingAyahs = "afterRepeatingAyahs"   // only first pass includes ayah repeats
}

/// How a CDN reciter's audio files are named.
enum ReciterNamingPattern: String, Codable {
    /// Files named {surah3}{ayah3}.{format} — e.g. 001001.mp3 (EveryAyah format)
    case surahAyah   = "surah_ayah"
    /// Files named by sequential ayah index 1–6236 — e.g. 1.mp3 (Al Quran Cloud format)
    case sequential  = "sequential"
    /// Full URL template with substitution tokens: ${s}, ${ss}, ${sss} (surah), ${a}, ${aa}, ${aaa} (ayah).
    /// The number of letters sets the minimum digit width (e.g. ${sss} → "001", ${s} → "1").
    /// Stored in Reciter.audioURLTemplate. remoteBaseURL is unused for this pattern.
    case urlTemplate = "url_template"
}
