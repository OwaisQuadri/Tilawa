import SwiftUI

struct SettingsView: View {
    @Environment(MushafViewModel.self) private var mushafVM

    var body: some View {
        @Bindable var vm = mushafVM

        NavigationStack {
            Form {
                Section("Font Size") {
                    HStack {
                        Button { vm.decreaseFontSize() } label: {
                            Image(systemName: "textformat.size.smaller")
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.fontSize <= QuranFontProvider.minFontSize)

                        Slider(value: $vm.fontSize, in: QuranFontProvider.minFontSize...QuranFontProvider.maxFontSize, step: 2)

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

                Section("Theme") {
                    Picker("Theme", selection: $vm.theme) {
                        Text("Light").tag(MushafTheme.light)
                        Text("Dark").tag(MushafTheme.dark)
                        Text("Sepia").tag(MushafTheme.sepia)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
