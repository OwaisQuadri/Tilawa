import SwiftUI

/// Compact persistent player bar shown above the tab bar during active playback.
struct MiniPlayerBar: View {
    @Environment(PlaybackViewModel.self) private var playback

    var body: some View {
        HStack(spacing: 0) {
            // Info area
            VStack(alignment: .leading, spacing: 2) {
                Text(playback.currentTrackTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(playback.currentReciterName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            // Playback controls
            HStack(spacing: 20) {
                Button {
                    Task { await playback.skipToPreviousAyah() }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.body)
                }

                Button {
                    if playback.isPlaying { playback.pause() } else { playback.resume() }
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 28, height: 28)
                }

                Button {
                    Task { await playback.skipToNextAyah() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                }

                Button {
                    playback.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
    }
}
