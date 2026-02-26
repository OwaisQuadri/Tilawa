import Foundation

// MARK: - Resolved playable unit for one ayah

/// The resolved, playable unit for a single ayah. Built by ReciterResolver.
/// Supports both full-file CDN audio (startOffset = 0) and UGC sub-file segments.
struct AyahAudioItem: Identifiable, Sendable {
    let id: UUID
    let ayahRef: AyahRef        // start of the covered ayah range
    let endAyahRef: AyahRef     // end of range (== ayahRef for single-ayah CDN items)
    let audioURL: URL
    let startOffset: TimeInterval   // 0 for full CDN files; >0 for UGC segments
    let endOffset: TimeInterval
    let reciterName: String
    let reciterId: UUID
    let isPersonalRecording: Bool

    var coversRange: Bool { endAyahRef != ayahRef }
}

// MARK: - Immutable settings snapshot

/// Immutable snapshot of PlaybackSettings captured at play() time.
/// Settings changes during a session do NOT affect the running session.
struct PlaybackSettingsSnapshot: Sendable {
    let range: AyahRange
    let connectionAyahBefore: Int
    let connectionAyahAfter: Int
    let speed: Double
    let ayahRepeatCount: Int        // -1 = infinite
    let rangeRepeatCount: Int       // -1 = infinite
    let afterRepeatAction: AfterRepeatAction
    let afterRepeatContinueAyaatCount: Int
    let afterRepeatContinuePagesCount: Int
    let afterRepeatContinuePagesExtraAyah: Bool
    let gapBetweenAyaatMs: Int
    let reciterPriority: [ReciterSnapshot]
    let riwayah: Riwayah
}

/// Snapshot of one priority entry (resolved Reciter object at capture time).
struct ReciterSnapshot: Sendable {
    let reciterId: UUID
    let reciter: Reciter
}

// MARK: - Word timing (retained for future use, not used by engine in this version)

struct WordTiming: Codable, Sendable {
    let wordIndex: Int          // 0-based index within the ayah
    let startSeconds: Double
    let endSeconds: Double
}
