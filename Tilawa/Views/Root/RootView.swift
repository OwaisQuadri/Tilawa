import SwiftUI

/// Root tab-based navigation for the app.
struct RootView: View {
    @Environment(PlaybackViewModel.self) private var playbackVM

    var body: some View {
        TabView {
            Tab("Mushaf", systemImage: "book") {
                MushafView()
                    .miniPlayerInset()
            }

            Tab("Reciters", systemImage: "person.wave.2") {
                RecitersView()
                    .miniPlayerInset()
            }

            Tab("Library", systemImage: "waveform") {
                LibraryView()
                    .miniPlayerInset()
            }

            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
                    .miniPlayerInset()
            }
        }
    }
}

private struct MiniPlayerInset: ViewModifier {
    @Environment(PlaybackViewModel.self) private var playbackVM

    private var showMiniPlayer: Bool {
        playbackVM.state.isActive || playbackVM.slidingWindow.isActive
    }

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if showMiniPlayer {
                MiniPlayerBar()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: showMiniPlayer)
    }
}

private extension View {
    func miniPlayerInset() -> some View {
        modifier(MiniPlayerInset())
    }
}
