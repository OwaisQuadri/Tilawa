import Foundation
import MediaPlayer

/// Registers and handles lock screen / control center remote commands.
final class RemoteCommandHandler {

    weak var engine: PlaybackEngine?
    // Retain the tokens returned by addTarget — handlers are removed when tokens are released
    private var tokens: [Any] = []

    func register(engine: PlaybackEngine) {
        self.engine = engine
        // Explicitly remove all targets before re-registering to avoid duplicate handlers
        unregister()

        let center = MPRemoteCommandCenter.shared()

        // togglePlayPauseCommand is what the lock screen widget and headphone button use
        center.togglePlayPauseCommand.isEnabled = true
        tokens.append(center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let engine = self?.engine else { return .noSuchContent }
            if engine.state == .playing { engine.pause() } else { engine.resume() }
            return .success
        })

        center.playCommand.isEnabled = true
        tokens.append(center.playCommand.addTarget { [weak self] _ in
            guard let engine = self?.engine else { return .noSuchContent }
            guard engine.state != .playing else { return .commandFailed }
            engine.resume()
            return .success
        })

        center.pauseCommand.isEnabled = true
        tokens.append(center.pauseCommand.addTarget { [weak self] _ in
            guard let engine = self?.engine else { return .noSuchContent }
            guard engine.state == .playing else { return .commandFailed }
            engine.pause()
            return .success
        })

        // stopCommand disabled — enabling it replaces the pause button in the widget
        center.stopCommand.isEnabled = false

        // Forward = next ayah
        center.nextTrackCommand.isEnabled = true
        tokens.append(center.nextTrackCommand.addTarget { [weak self] _ in
            guard let engine = self?.engine else { return .noSuchContent }
            Task { await engine.skipToNextAyah() }
            return .success
        })

        // Back = previous ayah
        center.previousTrackCommand.isEnabled = true
        tokens.append(center.previousTrackCommand.addTarget { [weak self] _ in
            guard let engine = self?.engine else { return .noSuchContent }
            Task { await engine.skipToPreviousAyah() }
            return .success
        })

        // Time scrubbing disabled — navigation is ayah-level only
        center.changePlaybackPositionCommand.isEnabled = false
    }

    func unregister() {
        tokens.removeAll()
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.removeTarget(nil)
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
    }
}
