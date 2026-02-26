import Foundation
import MediaPlayer

/// Updates the system Now Playing info center with current playback metadata.
final class NowPlayingCoordinator {

    private let metadata: QuranMetadataService

    init(metadata: QuranMetadataService = .shared) {
        self.metadata = metadata
    }

    func update(item: AyahAudioItem,
                state: PlaybackState,
                speed: Double,
                ayahRep: Int, totalAyahRep: Int,
                rangeRep: Int, totalRangeRep: Int,
                elapsed: TimeInterval) {

        let surahName = metadata.surahName(item.ayahRef.surah)
        // Each ayah is its own track: "Al-Fatiha - 1", "Al-Fatiha - 2", etc.
        let trackTitle = "\(surahName) - \(item.ayahRef.ayah)"

        let repLabel: String
        if totalRangeRep == -1 {
            repLabel = "Rep \(rangeRep) (∞)"
        } else if totalRangeRep > 1 {
            repLabel = "Rep \(rangeRep)/\(totalRangeRep)"
        } else {
            repLabel = ""
        }

        let duration = max(item.endOffset - item.startOffset, 0)

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: trackTitle,
            MPMediaItemPropertyArtist: item.reciterName,
            MPMediaItemPropertyAlbumTitle: repLabel,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? speed : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: speed,
            MPNowPlayingInfoPropertyMediaType: NSNumber(value: MPNowPlayingInfoMediaType.audio.rawValue),
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]

        // Ayah repeat progress (shown as disc number / disc count in some players)
        if totalAyahRep > 1 {
            info[MPMediaItemPropertyDiscNumber] = ayahRep
            info[MPMediaItemPropertyDiscCount] = totalAyahRep == -1 ? 0 : totalAyahRep
        }

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = state == .playing ? .playing : .paused
    }

    func clear() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }
}
