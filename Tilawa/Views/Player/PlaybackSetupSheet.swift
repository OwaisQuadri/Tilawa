import SwiftUI
import SwiftData

/// Sheet for configuring and starting a playback session.
struct PlaybackSetupSheet: View {
    @Environment(MushafViewModel.self) private var mushafVM
    @Environment(PlaybackViewModel.self) private var playback
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var allPlaybackSettings: [PlaybackSettings]
    @Query private var allReciters: [Reciter]
    private var settings: PlaybackSettings? { allPlaybackSettings.first }

    private let metadata   = QuranMetadataService.shared
    private let juzService = JuzService.shared
    private let rubService = RubService.shared

    // MARK: - Range state

    @State private var startSurah: Int = 1
    @State private var startAyah:  Int = 1
    @State private var endSurah:   Int = 1
    @State private var endAyah:    Int = 7

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                recitationSection
                rangeSection
                playbackSection
                repeatSection
            }
            .navigationTitle("Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: startPlayback) {
                        Label("Play", systemImage: "play.fill")
                            .font(.body.weight(.semibold))
                    }
                    .disabled(isPlayDisabled)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { initializeRange() }
    }

    // MARK: - Recitation section

    @ViewBuilder
    private var recitationSection: some View {
        if let s = settings {
            Section("Recitation") {
                // Riwayah
                LabeledContent("Riwayah") {
                    Picker("", selection: riwayahBinding(s)) {
                        ForEach(Riwayah.allCases, id: \.self) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: s.safeRiwayah) { _, newRiwayah in
                        // Reset reciter to Auto if it no longer matches the new riwayah
                        if let id = s.selectedReciterId,
                           let reciter = allReciters.first(where: { $0.id == id }),
                           reciter.safeRiwayah != newRiwayah {
                            s.selectedReciterId = nil
                            save()
                        }
                    }
                }

                // Reciter
                LabeledContent("Reciter") {
                    Picker("", selection: reciterBinding(s)) {
                        Text("Auto").tag(UUID?.none)
                        ForEach(matchingReciters(riwayah: s.safeRiwayah), id: \.id) { r in
                            Text(r.safeName).tag(r.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Inline error if no reciters match
                if matchingReciters(riwayah: s.safeRiwayah).isEmpty {
                    Text("No reciters available for this riwayah")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Auto priority link (shown when Auto is selected)
                if s.selectedReciterId == nil {
                    NavigationLink {
                        ReciterPriorityView()
                    } label: {
                        Label("Manage Auto Priority", systemImage: "arrow.up.arrow.down.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Range section

    @ViewBuilder
    private var rangeSection: some View {
        Section {
            // Preset chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.label) { preset in
                        Button(preset.label) { applyPreset(preset) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))

            // From row
            NavigationLink {
                RangePickerView(title: "From", surah: $startSurah, ayah: $startAyah)
                    .onDisappear { clampEndIfNeeded() }
            } label: {
                LabeledContent("From") {
                    Text("\(metadata.surahName(startSurah)) · \(startAyah)")
                        .foregroundStyle(.secondary)
                }
            }

            // To row
            NavigationLink {
                RangePickerView(title: "To", surah: $endSurah, ayah: $endAyah)
                    .onDisappear { clampEndIfNeeded() }
            } label: {
                LabeledContent("To") {
                    Text("\(metadata.surahName(endSurah)) · \(endAyah)")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Range")
        }
    }

    // MARK: - Playback section

    @ViewBuilder
    private var playbackSection: some View {
        if let s = settings {
            Section("Playback") {
                LabeledContent {
                    HStack {
                        Slider(value: speedBinding(s), in: 0.5...2.0, step: 0.25)
                        Text(speedLabel(s.safeSpeed))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                } label: {
                    Text("Speed")
                }

                Picker("Gap between ayaat", selection: gapBinding(s)) {
                    Text("None").tag(0)
                    Text("0.5 sec").tag(500)
                    Text("1 sec").tag(1000)
                    Text("2 sec").tag(2000)
                    Text("3 sec").tag(3000)
                }
            }
        }
    }

    // MARK: - Repeat section

    @ViewBuilder
    private var repeatSection: some View {
        if let s = settings {
            Section("Repeat") {
                Picker("Each verse", selection: ayahRepeatBinding(s)) {
                    ForEach(repeatOptions, id: \.tag) { opt in
                        Text(opt.label).tag(opt.tag)
                    }
                }

                Picker("Range", selection: rangeRepeatBinding(s)) {
                    ForEach(repeatOptions, id: \.tag) { opt in
                        Text(opt.label).tag(opt.tag)
                    }
                }

                if showAfterRepeat(s) {
                    Picker("After repeating", selection: afterRepeatBinding(s)) {
                        Text("Disabled").tag(0)
                        Text("3 ayaat").tag(3)
                        Text("5 ayaat").tag(5)
                        Text("10 ayaat").tag(10)
                        Text("1 page").tag(-100)
                    }
                }
            }
        }
    }

    // MARK: - Presets

    private struct Preset {
        let label: String
        let range: AyahRange
    }

    private var presets: [Preset] {
        var result: [Preset] = []
        let page = mushafVM.currentPage
        let juzInfo = juzService.juzInfo(forPage: page)

        // Current page — use the exact ayah range from the rendered page
        if let pageRange = mushafVM.currentPageAyahRange {
            result.append(Preset(label: "pg \(page)", range: AyahRange(start: pageRange.first, end: pageRange.last)))
        }

        // Each surah on current page
        if let pageRange = mushafVM.currentPageAyahRange {
            for s in pageRange.first.surah...pageRange.last.surah {
                let end = AyahRef(surah: s, ayah: metadata.ayahCount(surah: s))
                result.append(Preset(
                    label: metadata.surahName(s),
                    range: AyahRange(start: AyahRef(surah: s, ayah: 1), end: end)
                ))
            }
        }

        // Current juz — exact boundaries from rub metadata
        let juzRubs = rubService.rubRange(ofJuz: juzInfo.juz)
        if let first = rubService.firstAyah(ofRub: juzRubs.lowerBound),
           let last  = rubService.lastAyah(ofRub: juzRubs.upperBound) {
            result.append(Preset(
                label: "Juz \(juzInfo.juz)",
                range: AyahRange(start: first, end: last)
            ))
        }

        // Current hizb — exact boundaries from rub metadata
        let hizbRubs = rubService.rubRange(ofHizb: juzInfo.hizb)
        if let first = rubService.firstAyah(ofRub: hizbRubs.lowerBound),
           let last  = rubService.lastAyah(ofRub: hizbRubs.upperBound) {
            result.append(Preset(
                label: "Hizb \(juzInfo.hizb)",
                range: AyahRange(start: first, end: last)
            ))
        }

        // Current thumun — exact boundaries from rub metadata
        let rubNum = juzInfo.thumun  // global rub number 1-240
        if let first = rubService.firstAyah(ofRub: rubNum),
           let last  = rubService.lastAyah(ofRub: rubNum) {
            let fracs = ["", " ¼", " ½", " ¾"]
            let label = "Thumun @ Hizb \(juzInfo.hizb)\(fracs[juzInfo.thumunInHizb - 1])"
            result.append(Preset(
                label: label,
                range: AyahRange(start: first, end: last)
            ))
        }

        return result
    }

    private func applyPreset(_ preset: Preset) {
        startSurah = preset.range.start.surah
        startAyah  = preset.range.start.ayah
        endSurah   = preset.range.end.surah
        endAyah    = preset.range.end.ayah
        clampEndIfNeeded()
    }

    // MARK: - Helpers

    private func initializeRange() {
        // Long-press "Play Ayah" — seed range to exactly that one ayah, then consume
        if let ayah = mushafVM.longPressedAyahRef {
            startSurah = ayah.surah;  startAyah = ayah.ayah
            endSurah   = ayah.surah;  endAyah   = ayah.ayah
            mushafVM.longPressedAyahRef = nil
            return
        }
        let page = mushafVM.currentPage
        if let r = mushafVM.currentPageAyahRange {
            startSurah = r.first.surah;  startAyah = r.first.ayah
            endSurah   = r.last.surah;   endAyah   = r.last.ayah
        } else if let surah = metadata.surahOnPage(page) {
            startSurah = surah.number;   startAyah = 1
            endSurah   = surah.number;   endAyah   = metadata.ayahCount(surah: surah.number)
        }
    }

    private func clampEndIfNeeded() {
        if endSurah < startSurah {
            endSurah = startSurah
            endAyah  = metadata.ayahCount(surah: endSurah)
        } else if endSurah == startSurah && endAyah < startAyah {
            endAyah = startAyah
        }
    }

    private var isPlayDisabled: Bool {
        guard let s = settings else { return true }
        if let id = s.selectedReciterId {
            return allReciters.first(where: { $0.id == id }) == nil
        }
        return matchingReciters(riwayah: s.safeRiwayah).isEmpty
    }

    private func matchingReciters(riwayah: Riwayah) -> [Reciter] {
        allReciters.filter { $0.safeRiwayah == riwayah }
    }

    private func showAfterRepeat(_ s: PlaybackSettings) -> Bool {
        guard (s.rangeRepeatCount ?? 1) != -1 else { return false }
        let riwayah = s.safeRiwayah
        if let id = s.selectedReciterId {
            return allReciters.first(where: { $0.id == id })?.hasCDN == true
        }
        return allReciters.contains { $0.safeRiwayah == riwayah && $0.hasCDN }
    }

    private func speedLabel(_ speed: Double) -> String {
        speed == 1.0 ? "1×" : String(format: "%.2g×", speed)
    }

    private var repeatOptions: [(label: String, tag: Int)] {
        [(label: "1×", tag: 1), (label: "3×", tag: 3), (label: "5×", tag: 5),
         (label: "10×", tag: 10), (label: "20×", tag: 20), (label: "30×", tag: 30),
         (label: "50×", tag: 50), (label: "100×", tag: 100), (label: "∞", tag: -1)]
    }

    private func startPlayback() {
        guard let s = settings else { return }
        let range = AyahRange(
            start: AyahRef(surah: startSurah, ayah: startAyah),
            end:   AyahRef(surah: endSurah,   ayah: endAyah)
        )
        let capturedPlayback = playback
        let capturedContext  = context
        dismiss()
        Task { await capturedPlayback.play(range: range, settings: s, context: capturedContext) }
    }

    // MARK: - Settings bindings

    private func riwayahBinding(_ s: PlaybackSettings) -> Binding<Riwayah> {
        Binding(
            get: { s.safeRiwayah },
            set: { s.selectedRiwayah = $0.rawValue; save() }
        )
    }

    private func reciterBinding(_ s: PlaybackSettings) -> Binding<UUID?> {
        Binding(
            get: { s.selectedReciterId },
            set: { s.selectedReciterId = $0; save() }
        )
    }

    private func speedBinding(_ s: PlaybackSettings) -> Binding<Double> {
        Binding(get: { s.safeSpeed }, set: { s.playbackSpeed = $0; save() })
    }

    private func gapBinding(_ s: PlaybackSettings) -> Binding<Int> {
        Binding(get: { s.safeGapMs }, set: { s.gapBetweenAyaatMs = $0; save() })
    }

    private func ayahRepeatBinding(_ s: PlaybackSettings) -> Binding<Int> {
        Binding(get: { s.safeAyahRepeat }, set: { s.ayahRepeatCount = $0; save() })
    }

    private func rangeRepeatBinding(_ s: PlaybackSettings) -> Binding<Int> {
        Binding(get: { s.safeRangeRepeat }, set: { s.rangeRepeatCount = $0; save() })
    }

    /// Encodes afterRepeatAction + count into a single Int tag for the picker.
    /// 0 = stop, 3/5/10 = continueAyaat with that count, -100 = continuePages(1)
    private func afterRepeatBinding(_ s: PlaybackSettings) -> Binding<Int> {
        Binding(
            get: {
                switch s.safeAfterRepeatAction {
                case .stop:           return 0
                case .continueAyaat:  return s.afterRepeatContinueAyaatCount ?? 3
                case .continuePages:  return -100
                }
            },
            set: { tag in
                switch tag {
                case 0:
                    s.afterRepeatAction = AfterRepeatAction.stop.rawValue
                case -100:
                    s.afterRepeatAction = AfterRepeatAction.continuePages.rawValue
                    s.afterRepeatContinuePagesCount = 1
                default:
                    s.afterRepeatAction = AfterRepeatAction.continueAyaat.rawValue
                    s.afterRepeatContinueAyaatCount = tag
                }
                save()
            }
        )
    }

    private func save() { try? context.save() }
}
