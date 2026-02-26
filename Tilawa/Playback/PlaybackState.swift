import Foundation

/// Engine state machine — 8 states with 12 transitions.
///
/// ```
/// idle            --[play(range:settings:)]-->  loading
/// loading         --[itemReady]             -->  playing
/// loading         --[itemUnavailable]       -->  loading (try next reciter) | error (all failed)
/// playing         --[pause()]               -->  paused
/// paused          --[resume()]              -->  playing
/// playing         --[ayahComplete]          -->  awaitingRepeat   (if ayahRepeat > 1 remaining)
///                                           -->  awaitingNextAyah (if ayahRepeat exhausted)
/// awaitingRepeat  --[gapElapsed]            -->  loading (reload same ayah)
/// awaitingNextAyah--[hasMoreAyaat]          -->  loading (next ayah in range)
/// awaitingNextAyah--[rangeEnd]              -->  awaitingNextAyah (decrement rangeRepeat)
///                                           -->  rangeComplete (rangeRepeat exhausted)
/// rangeComplete   --[.stop]                 -->  idle
/// rangeComplete   --[.continueAyaat(N)]     -->  loading
/// rangeComplete   --[.continuePages(N)]     -->  loading
/// any             --[stop()]                -->  idle
/// any             --[seek(to:)]             -->  loading
/// ```
enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case awaitingRepeat
    case awaitingNextAyah
    case rangeComplete
    case error(PlaybackError)

    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.loading, .loading),
             (.playing, .playing),
             (.paused, .paused),
             (.awaitingRepeat, .awaitingRepeat),
             (.awaitingNextAyah, .awaitingNextAyah),
             (.rangeComplete, .rangeComplete):
            return true
        case (.error(let a), .error(let b)):
            return a.localizedDescription == b.localizedDescription
        default:
            return false
        }
    }
}

extension PlaybackState {
    /// True whenever the engine has an active session (not idle, not complete, not errored).
    var isActive: Bool {
        switch self {
        case .idle, .rangeComplete, .error: return false
        default: return true
        }
    }

    /// True only when audio is actively rendering or paused mid-session.
    var isPlayingOrPaused: Bool { self == .playing || self == .paused }
}

enum PlaybackError: Error {
    case noRecitersConfigured
    case noAudioAvailable(AyahRef)
    case audioLoadFailed(URL, Error)
    case engineStartFailed(Error)
}
