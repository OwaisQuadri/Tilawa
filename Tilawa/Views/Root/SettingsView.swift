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

                // MARK: - Playback
                Section("Playback") {
                    // Reciters
                    if allReciters.isEmpty {
                        LabeledContent("Reciters", value: "None configured")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(allReciters) { reciter in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reciter.safeName)
                                        .font(.body)
                                    Text(reciter.safeRiwayah.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if reciter.isDownloaded == true {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }

                // MARK: - Playback Options
                if let settings = activeSettings {
                    Section("Options") {
                        // Speed
                        Picker("Speed", selection: speedBinding(settings)) {
                            Text("0.5×").tag(0.5)
                            Text("0.75×").tag(0.75)
                            Text("1×").tag(1.0)
                            Text("1.25×").tag(1.25)
                            Text("1.5×").tag(1.5)
                            Text("2×").tag(2.0)
                        }

                        // Gap between ayaat
                        Picker("Gap between ayaat", selection: gapBinding(settings)) {
                            Text("None").tag(0)
                            Text("0.5 sec").tag(500)
                            Text("1 sec").tag(1000)
                            Text("2 sec").tag(2000)
                            Text("3 sec").tag(3000)
                        }

                        // Ayah repeat
                        Picker("Ayah repeat", selection: ayahRepeatBinding(settings)) {
                            Text("1×").tag(1)
                            Text("2×").tag(2)
                            Text("3×").tag(3)
                            Text("5×").tag(5)
                            Text("10×").tag(10)
                            Text("∞").tag(-1)
                        }

                        // Range repeat
                        Picker("Range repeat", selection: rangeRepeatBinding(settings)) {
                            Text("1×").tag(1)
                            Text("2×").tag(2)
                            Text("3×").tag(3)
                            Text("5×").tag(5)
                            Text("∞").tag(-1)
                        }
                    }
                }

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
                    .pickerStyle(.segmented)
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
