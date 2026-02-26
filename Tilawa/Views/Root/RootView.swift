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

            Tab("Library", systemImage: "waveform") {
                Text("Recording Library")
                    .foregroundStyle(.secondary)
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

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if playbackVM.state.isActive {
                MiniPlayerBar()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: playbackVM.state.isActive)
    }
}

private extension View {
    func miniPlayerInset() -> some View {
        modifier(MiniPlayerInset())
    }
}
