import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(MushafViewModel.self) private var mushafVM
    @Environment(PlaybackViewModel.self) private var playback
    @Environment(\.modelContext) private var context

    @Query private var allPlaybackSettings: [PlaybackSettings]
    @Query private var allReciters: [Reciter]

    private var activeSettings: PlaybackSettings? { allPlaybackSettings.first }

    var body: some View {
        @Bindable var vm = mushafVM

        NavigationStack {
            Form {
                // MARK: - Font Size
                Section("Font Size") {
                    HStack {
                        Button { vm.decreaseFontSize() } label: {
                            Image(systemName: "textformat.size.smaller")
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.fontSize <= QuranFontProvider.minFontSize)

                        Slider(value: $vm.fontSize,
                               in: QuranFontProvider.minFontSize...QuranFontProvider.maxFontSize,
                               step: 2)

                        Button { vm.increaseFontSize() } label: {
                            Image(systemName: "textformat.size.larger")
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.fontSize >= QuranFontProvider.maxFontSize)
                    }

                    Text("\(Int(vm.fontSize)) pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                // MARK: - Theme
                Section("Theme") {
                    Picker("Theme", selection: $vm.theme) {
                        Text("Default").tag(MushafTheme.standard)
                        Text("Sepia").tag(MushafTheme.sepia)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Settings bindings (read/write to SwiftData model)

    private func speedBinding(_ s: PlaybackSettings) -> Binding<Double> {
        Binding(
            get: { s.playbackSpeed ?? 1.0 },
            set: { s.playbackSpeed = $0; saveContext() }
        )
    }

    private func gapBinding(_ s: PlaybackSettings) -> Binding<Int> {
        Binding(
            get: { s.gapBetweenAyaatMs ?? 0 },
            set: { s.gapBetweenAyaatMs = $0; saveContext() }
        )
    }

    private func ayahRepeatBinding(_ s: PlaybackSettings) -> Binding<Int> {
        Binding(
            get: { s.ayahRepeatCount ?? 1 },
            set: { s.ayahRepeatCount = $0; saveContext() }
        )
    }

    private func rangeRepeatBinding(_ s: PlaybackSettings) -> Binding<Int> {
        Binding(
            get: { s.rangeRepeatCount ?? 1 },
            set: { s.rangeRepeatCount = $0; saveContext() }
        )
    }

    private func saveContext() {
        try? context.save()
    }
}
