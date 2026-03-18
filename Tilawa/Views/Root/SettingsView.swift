import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(MushafViewModel.self) private var mushafVM
    @Environment(PlaybackViewModel.self) private var playback
    @Environment(\.modelContext) private var context

    @Query private var allPlaybackSettings: [PlaybackSettings]
    @Query private var allReciters: [Reciter]

    @AppStorage("settings.hapticsEnabled") private var hapticsEnabled = true

    @State private var totalCacheBytes: Int64 = 0
    @State private var isLoadingStorage = false
    @State private var showClearAllConfirmation = false
    @State private var showDownloadPrompt = false
    @State private var showIndopakDownloadPrompt = false
    @State private var riwayahToDownload: Riwayah?

    private var activeSettings: PlaybackSettings? { allPlaybackSettings.first }

    private var appVersion: String {
        let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }

    var body: some View {
        @Bindable var vm = mushafVM

        NavigationStack {
            Form {
                // MARK: - Mushaf Riwayah
                Section("Mushaf Riwayah") {
                    Picker("Riwayah", selection: $vm.activeRiwayah) {
                        ForEach(Riwayah.availableForMushaf) { riwayah in
                            HStack {
                                Text(riwayah.displayName)
                                if riwayah.renderingMode == .pdf {
                                    Spacer()
                                    PDFDownloadBadge(riwayah: riwayah)
                                }
                            }
                            .tag(riwayah)
                        }
                    }
                }
                .onChange(of: vm.activeRiwayah) { _, newRiwayah in
                    if newRiwayah.renderingMode == .pdf && !MushafPDFManager.shared.isDownloaded(newRiwayah) {
                        riwayahToDownload = newRiwayah
                        showDownloadPrompt = true
                    }
                }

                // MARK: - Hafs-only: Font & Theme
                if vm.activeRiwayah == .hafs {
                    Section("Font") {
                        Picker("Mushaf Style", selection: $vm.mushafStyle) {
                            ForEach(MushafViewModel.MushafStyle.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                    }
                    .onChange(of: vm.mushafStyle) { _, newStyle in
                        if newStyle == .indopak && !MushafPDFManager.shared.isIndopakDownloaded {
                            showIndopakDownloadPrompt = true
                        }
                    }
                }

                // Font size controls for glyph and unicode text rendering
                if vm.effectiveRenderingMode == .hafsGlyph || vm.effectiveRenderingMode == .unicodeText {
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
                }

                // Theme controls for non-PDF rendering
                if vm.effectiveRenderingMode != .pdf {
                    Section("Theme") {
                        Picker("Theme", selection: $vm.theme) {
                            Text("Default").tag(MushafTheme.standard)
                            Text("Sepia").tag(MushafTheme.sepia)
                        }
                    }
                }

                // MARK: - Display
                Section("Display") {
                    Toggle("Page Side Indicators", isOn: $vm.showSideIndicators)
                    Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                }

                // MARK: - Downloaded Mushafs
                if !downloadedPDFs.isEmpty {
                    Section("Downloaded Mushafs") {
                        ForEach(downloadedPDFs, id: \.filename) { item in
                            HStack {
                                Text(item.label)
                                Spacer()
                                Text(formattedBytes(item.size))
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    item.delete()
                                }
                            }
                        }
                    }
                }

                // MARK: - Storage
                Section {
                    Button(role: .destructive) {
                        showClearAllConfirmation = true
                    } label: {
                        if isLoadingStorage {
                            HStack {
                                Text("Clear Cache")
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                        } else {
                            Text("Clear Cache (\(formattedBytes(totalCacheBytes)))")
                        }
                    }
                    .disabled(totalCacheBytes == 0)
                } footer: {
                    Text("Removes cached CDN audio. Does not affect personal recordings or downloaded mushafs.")
                        .font(.caption)
                }
                .confirmationDialog("Clear All Cache?", isPresented: $showClearAllConfirmation) {
                    Button("Delete All Cached Audio", role: .destructive) {
                        Haptics.notification(.warning)
                        Task { await clearAllCache() }
                    }
                } message: {
                    Text("This will delete \(formattedBytes(totalCacheBytes)) of cached audio. Files can be re-downloaded.")
                }

                // MARK: - About
                Section {
                    LabeledContent("Version", value: appVersion)
                }

            }
            .task { await loadStorageInfo() }
            .navigationTitle("Settings")
            .alert("Download Mushaf", isPresented: $showDownloadPrompt) {
                Button("Download") {
                    guard let riwayah = riwayahToDownload else { return }
                    Task {
                        try? await MushafPDFManager.shared.download(riwayah)
                    }
                }
                Button("Cancel", role: .cancel) {
                    // Revert to Hafs if they cancel
                    mushafVM.activeRiwayah = .hafs
                }
            } message: {
                if let riwayah = riwayahToDownload {
                    Text("The \(riwayah.displayName) mushaf needs to be downloaded first.")
                } else {
                    Text("This mushaf needs to be downloaded first.")
                }
            }
            .alert("Download Indopak Mushaf", isPresented: $showIndopakDownloadPrompt) {
                Button("Download") {
                    Task { try? await MushafPDFManager.shared.downloadIndopak() }
                }
                Button("Cancel", role: .cancel) {
                    mushafVM.mushafStyle = .uthmani
                }
            } message: {
                Text("The Indopak 15-line mushaf needs to be downloaded (~85 MB).")
            }
        }
    }

    // MARK: - Downloaded PDFs

    private struct DownloadedPDFItem {
        let filename: String
        let label: String
        let size: Int64
        let delete: () -> Void
    }

    private var downloadedPDFs: [DownloadedPDFItem] {
        let mgr = MushafPDFManager.shared
        var items: [DownloadedPDFItem] = []

        // Group riwayahs by their shared PDF filename
        var fileToRiwayahs: [String: [Riwayah]] = [:]
        for riwayah in Riwayah.allCases {
            guard let source = mgr.source(for: riwayah), mgr.isDownloaded(riwayah) else { continue }
            fileToRiwayahs[source.filename, default: []].append(riwayah)
        }

        for (filename, riwayahs) in fileToRiwayahs.sorted(by: { $0.key < $1.key }) {
            let size = mgr.downloadedSize(for: riwayahs[0])
            let label = riwayahs.map(\.displayName).joined(separator: " / ")
            let firstRiwayah = riwayahs[0]
            items.append(DownloadedPDFItem(
                filename: filename,
                label: label,
                size: size,
                delete: { try? mgr.deleteDownload(for: firstRiwayah) }
            ))
        }

        if mgr.isIndopakDownloaded {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs.appendingPathComponent("MushafPDFs/\(MushafPDFManager.indopakSource.filename)")
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            items.append(DownloadedPDFItem(
                filename: MushafPDFManager.indopakSource.filename,
                label: "Hafs 'an 'Asim (Indopak 15-line)",
                size: size,
                delete: { try? mgr.deleteIndopak() }
            ))
        }

        return items
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

    // MARK: - Storage helpers

    private func loadStorageInfo() async {
        isLoadingStorage = true
        totalCacheBytes = await AudioFileCache.shared.totalCacheSize()
        isLoadingStorage = false
    }

    private func clearAllCache() async {
        let cache = AudioFileCache.shared
        try? await cache.deleteAllCache()
        for reciter in allReciters where reciter.hasCDN {
            reciter.downloadedSurahsJSON = nil
            reciter.isDownloaded = false
        }
        saveContext()
        await loadStorageInfo()
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

}

// MARK: - PDF Download Badge

private struct PDFDownloadBadge: View {
    let riwayah: Riwayah

    var body: some View {
        let state = MushafPDFManager.shared.downloadState(for: riwayah)
        switch state {
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .downloading(let progress):
            ProgressView(value: progress)
                .frame(width: 40)
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}
