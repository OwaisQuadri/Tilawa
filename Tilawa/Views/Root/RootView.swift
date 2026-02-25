import SwiftUI

/// Root tab-based navigation for the app.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Mushaf", systemImage: "book") {
                MushafView()
            }

            Tab("Library", systemImage: "waveform") {
                Text("Recording Library")
                    .foregroundStyle(.secondary)
            }

            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}
