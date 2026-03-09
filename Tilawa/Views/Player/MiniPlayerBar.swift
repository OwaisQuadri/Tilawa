import SwiftUI

// MARK: - Phase Icons (edit these to change which SF Symbols are used)

private enum PhaseIcons {
    static let solo       = "square.3.stack.3d.middle.filled"
    static let connection = "link"
    static let fullRange  = "square.stack.3d.up.fill"
    static let idle       = "circle"

    static let ayahRepeat = "repeat.1"
    static let rangeRepeat = "repeat"
    static let afterRepeat = "arrow.turn.down.right"
}

// MARK: - MiniPlayerBar

/// Compact persistent player bar shown above the tab bar during active playback.
struct MiniPlayerBar: View {
    @Environment(PlaybackViewModel.self) private var playback
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 0) {
            // Info area — tapping opens current playback settings
            Button {
                showingSettings = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.currentTrackTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(playback.currentReciterName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    RepetitionIndicator(playback: playback)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)

            // Playback controls
            HStack(spacing: 16) {
                Button {
                    Task { await playback.skipToPreviousAyah() }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.body)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }

                Button {
                    if playback.isPlayingOrLoading { playback.pause() } else { playback.resume() }
                } label: {
                    Image(systemName: playback.isPlayingOrLoading ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }

                Button {
                    Task { await playback.skipToNextAyah() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }

                Button {
                    playback.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        .sheet(isPresented: $showingSettings) {
            PlaybackSetupSheet(initialRange: playback.activeRange)
        }
    }
}

// MARK: - Repetition Indicator

/// Shows repetition counters and sliding window phase using icons.
private struct RepetitionIndicator: View {
    let playback: PlaybackViewModel

    /// Resolves the after-repeat option from the correct source:
    /// coordinator's base snapshot for sliding window, engine's active snapshot for standard.
    private var afterRepeatOption: AfterRepeatOption {
        playback.slidingWindow.isActive
            ? playback.slidingWindow.afterRepeatOption
            : playback.afterRepeatOption
    }

    var body: some View {
        HStack(spacing: 6) {
            if playback.slidingWindow.isActive {
                slidingWindowChips
            } else {
                standardChips
            }

            // After-repeat continuation indicator (shared across both modes)
            // In sliding window mode, the engine always sees .stop (per-phase snapshot),
            // so read the real config from the coordinator's base snapshot instead.
            if afterRepeatOption != .disabled {
                chip(icon: PhaseIcons.afterRepeat, text: afterRepeatOption.shortLabel ?? "")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Sliding Window

    @ViewBuilder
    private var slidingWindowChips: some View {
        let sw = playback.slidingWindow
        let showEngine = playback.state.isActive

        // Phase indicator
        swPhaseChip(sw: sw)

        if showEngine {
            if playback.totalAyahRepetitions != 1 {
                chip(
                    icon: PhaseIcons.ayahRepeat,
                    text: playback.totalAyahRepetitions == -1
                        ? "∞"
                        : "\(playback.currentAyahRepetition)/\(playback.totalAyahRepetitions)"
                )
                .foregroundStyle(Color.accentColor)
            }
            if playback.totalRangeRepetitions != 1 {
                chip(
                    icon: PhaseIcons.rangeRepeat,
                    text: playback.totalRangeRepetitions == -1
                        ? "∞"
                        : "\(playback.currentRangeRepetition)/\(playback.totalRangeRepetitions)"
                )
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func swPhaseChip(sw: SlidingWindowCoordinator) -> some View {
        let icon: String = {
            switch sw.phase {
            case .solo:       return PhaseIcons.solo
            case .connection: return PhaseIcons.connection
            case .fullRange:  return PhaseIcons.fullRange
            default:          return PhaseIcons.idle
            }
        }()

        return HStack(spacing: 2) {
            Image(systemName: icon)
            if sw.phase != .fullRange {
                Text("\(sw.currentAyahIndex + 1)/\(sw.totalAyahCount)")
            }
        }
        .font(.caption2.weight(.semibold))
        .imageScale(.small)
        .foregroundStyle(Color.primary)
    }

    // MARK: Standard

    @ViewBuilder
    private var standardChips: some View {
        let hasAyah = playback.totalAyahRepetitions != 1
        let hasRange = playback.totalRangeRepetitions != 1

        if hasAyah || hasRange {
            // Phase chip with ayah position
            standardPhaseChip

            if hasAyah {
                chip(
                    icon: PhaseIcons.ayahRepeat,
                    text: playback.totalAyahRepetitions == -1
                        ? "∞"
                        : "\(playback.currentAyahRepetition)/\(playback.totalAyahRepetitions)"
                )
                .foregroundStyle(Color.accentColor)
            }
            if hasRange {
                chip(
                    icon: PhaseIcons.rangeRepeat,
                    text: playback.totalRangeRepetitions == -1
                        ? "∞"
                        : "\(playback.currentRangeRepetition)/\(playback.totalRangeRepetitions)"
                )
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var standardPhaseChip: some View {
        let icon = playback.totalAyahRepetitions != 1 ? PhaseIcons.solo : PhaseIcons.fullRange
        let count = playback.queueCount
        return HStack(spacing: 2) {
            Image(systemName: icon)
            if count > 1 {
                Text("\(playback.queueIndex + 1)/\(count)")
            }
        }
        .font(.caption2.weight(.semibold))
        .imageScale(.small)
        .foregroundStyle(Color.primary)
    }

    // MARK: Shared

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
            if !text.isEmpty {
                Text(text)
            }
        }
        .font(.caption2.weight(.medium))
        .imageScale(.small)
    }
}
