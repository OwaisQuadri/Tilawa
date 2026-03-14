import SwiftUI
import SwiftData

/// Sheet for configuring and starting a playback session.
struct PlaybackSetupSheet: View {
    /// When non-nil, seeds the range pickers from this value instead of the current Mushaf page.
    /// Used when opening the sheet from the mini player to restore the active session range.
    var initialRange: AyahRange? = nil

    @Environment(MushafViewModel.self) private var mushafVM
    @Environment(PlaybackViewModel.self) private var playback
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var allPlaybackSettings: [PlaybackSettings]
    @Query(sort: \SlidingWindowPreset.order) private var userPresets: [SlidingWindowPreset]
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
    @State private var isCheckingAvailability = false
    @State private var estimatedDuration: TimeInterval?
    @State private var estimateIsInfinite = false

    // Sliding window preset save/delete state
    @State private var showingSavePresetAlert = false
    @State private var newPresetName = ""
    @State private var presetToDelete: SlidingWindowPreset?

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
        .onAppear { initializeRange(); snapReciterSelectionIfNeeded(); snapRangeToAvailableIfNeeded(); triggerAvailabilityChecksIfNeeded() }
    }

    // MARK: - Recitation section

    @ViewBuilder
    private var recitationSection: some View {
        if let s = settings {
            Section("Recitation") {
                // Riwayah
                LabeledContent("Riwayah") {
                    Picker("", selection: riwayahBinding(s)) {
                        ForEach(availableRiwayat(for: s), id: \.self) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: s.safeRiwayah) { _, newRiwayah in
                        // Reset reciter to Auto if it no longer has sources for the new riwayah
                        if let id = s.selectedReciterId,
                           !matchingReciters(riwayah: newRiwayah).contains(where: { $0.id == id }) {
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

                // Inline error if no enabled reciters match
                if enabledMatchingReciters(riwayah: s.safeRiwayah, settings: s).isEmpty {
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
        let (allowedStart, allowedEnd) = allowedAyahRanges
        Section {
            // Preset chips — only show ranges fully covered by the selected reciter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets.filter { isPresetFullyAvailable($0) }, id: \.label) { preset in
                        Button(preset.label) { applyPreset(preset) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))

            // From row — restricted to valid start ayahs
            NavigationLink {
                RangePickerView(title: "From", surah: $startSurah, ayah: $startAyah,
                                allowedAyahs: allowedStart)
                    .onDisappear { clampEndIfNeeded() }
            } label: {
                LabeledContent("From") {
                    Text("\(metadata.surahName(startSurah)) · \(startAyah)")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isCheckingAvailability)

            // To row — restricted to valid end ayahs
            NavigationLink {
                RangePickerView(title: "To", surah: $endSurah, ayah: $endAyah,
                                allowedAyahs: allowedEnd)
                    .onDisappear { clampEndIfNeeded() }
            } label: {
                LabeledContent("To") {
                    Text("\(metadata.surahName(endSurah)) · \(endAyah)")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isCheckingAvailability)

            if rangeHasSkips {
                Text("Warning: this range covers ayaat that will be skipped due to missing audio.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if isCheckingAvailability {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Checking available ayaat…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Range")
        }
        .onChange(of: settings?.selectedReciterId) { _, _ in
            snapRangeToAvailableIfNeeded()
            triggerAvailabilityChecksIfNeeded()
        }
        .onChange(of: settings?.selectedRiwayah) { _, _ in
            snapRangeToAvailableIfNeeded()
            triggerAvailabilityChecksIfNeeded()
        }
    }

    // MARK: - Playback section

    @ViewBuilder
    private var playbackSection: some View {
        if let s = settings {
            Section {
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
            } header: {
                Text("Playback")
            } footer: {
                Text(estimatedTimeLabel)
            }
            .task(id: estimateInputs) {
                await computeEstimatedDuration()
            }
        }
    }

    // MARK: - Repeat section

    @ViewBuilder
    private var repeatSection: some View {
        if let s = settings {
            Section("Repeat") {
                Picker("Mode", selection: slidingWindowEnabledBinding(s)) {
                    Text("Standard").tag(false)
                    Text("Sliding Window").tag(true)
                }

                if s.safeSlidingWindowEnabled {
                    // Sliding window preset chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button("Default") {
                                applySWSettings(.default, to: s)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(currentSWSettings(s) == .default ? .accentColor : nil)

                            ForEach(userPresets) { preset in
                                Button {
                                    applySWSettings(preset.settings, to: s)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(preset.safeName)
                                        Button {
                                            presetToDelete = preset
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(preset.matches(currentSWSettings(s)) ? .accentColor : nil)
                            }

                            Button {
                                newPresetName = ""
                                showingSavePresetAlert = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))

                    Picker("Solo repeats", selection: swPerAyahBinding(s)) {
                        ForEach(1...20, id: \.self) { n in Text("\(n)×").tag(n) }
                    }
                    Picker("Connection repeats", selection: swConnectionRepeatsBinding(s)) {
                        ForEach(1...10, id: \.self) { n in Text("\(n)×").tag(n) }
                    }
                    Picker("Connection ayahs", selection: swConnectionWindowBinding(s)) {
                        ForEach(1...10, id: \.self) { n in Text("\(n)").tag(n) }
                    }
                    Picker("Full range repeats", selection: swFullRangeBinding(s)) {
                        ForEach(1...30, id: \.self) { n in Text("\(n)×").tag(n) }
                    }

                    Text(slidingWindowSummary(s))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
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

                    if showRangeRepeatBehavior(s) {
                        Picker("Verse repeats", selection: rangeRepeatBehaviorBinding(s)) {
                            Text("Every range pass").tag(RangeRepeatBehavior.whileRepeatingAyahs)
                            Text("First pass only").tag(RangeRepeatBehavior.afterRepeatingAyahs)
                        }
                    }
                }

                if showAfterRepeat(s) {
                    Picker("After repeating", selection: afterRepeatBinding(s)) {
                        ForEach(AfterRepeatOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }
            }
            .alert("Save Preset", isPresented: $showingSavePresetAlert) {
                TextField("Preset name", text: $newPresetName)
                Button("Save") { saveCurrentAsPreset(s) }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete Preset?",
                                isPresented: Binding(
                                    get: { presetToDelete != nil },
                                    set: { if !$0 { presetToDelete = nil } }
                                ),
                                titleVisibility: .visible) {
                if let preset = presetToDelete {
                    Button("Delete \"\(preset.safeName)\"", role: .destructive) {
                        context.delete(preset)
                        save()
                        presetToDelete = nil
                    }
                }
            }
        }
    }

    private func currentSWSettings(_ s: PlaybackSettings) -> SlidingWindowSettings {
        SlidingWindowSettings(
            perAyahRepeats: s.safeSWPerAyahRepeats,
            connectionRepeats: s.safeSWConnectionRepeats,
            connectionWindowSize: s.safeSWConnectionWindow,
            fullRangeRepeats: s.safeSWFullRangeRepeats
        )
    }

    private func applySWSettings(_ sw: SlidingWindowSettings, to s: PlaybackSettings) {
        s.slidingWindowPerAyahRepeats = sw.perAyahRepeats
        s.slidingWindowConnectionRepeats = sw.connectionRepeats
        s.slidingWindowConnectionWindow = sw.connectionWindowSize
        s.slidingWindowFullRangeRepeats = sw.fullRangeRepeats
        save()
    }

    private func saveCurrentAsPreset(_ s: PlaybackSettings) {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let preset = SlidingWindowPreset.make(
            name: name,
            settings: currentSWSettings(s),
            order: userPresets.count
        )
        context.insert(preset)
        save()
    }

    private func slidingWindowSummary(_ s: PlaybackSettings) -> String {
        let a = s.safeSWPerAyahRepeats
        let b = s.safeSWConnectionRepeats
        let c = s.safeSWConnectionWindow
        let d = s.safeSWFullRangeRepeats
        return "Each ayah \(a)x solo, then \(b)x with \(c) preceding, then \(d)x full range"
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

        // Current page + 1 ayah — current page plus the first ayah of the next page
        if let pageRange = mushafVM.currentPageAyahRange,
           let nextAyah = metadata.ayah(after: pageRange.last) {
            result.append(Preset(
                label: "pg \(page) +1a",
                range: AyahRange(start: pageRange.first, end: nextAyah)
            ))
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
        // Mini player / active session — restore the playing range
        if let range = initialRange {
            startSurah = range.start.surah;  startAyah = range.start.ayah
            endSurah   = range.end.surah;    endAyah   = range.end.ayah
            return
        }
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
        return enabledMatchingReciters(riwayah: s.safeRiwayah, settings: s).isEmpty
    }

    /// Reciters that have at least one audio source for the given riwayah (exact or compatible).
    /// CDN sources are matched by exact or ever-compatible riwayah;
    /// personal-recording reciters are matched by segment riwayah.
    private func matchingReciters(riwayah: Riwayah) -> [Reciter] {
        let everCompat = RiwayahCompatibilityService.shared.everCompatible(with: riwayah)
        return allReciters.filter { r in
            if (r.cdnSources ?? []).contains(where: {
                guard let raw = $0.riwayah, let cdnR = Riwayah(rawValue: raw) else { return false }
                return everCompat.contains(cdnR)
            }) { return true }
            return (r.segments ?? []).contains { everCompat.contains($0.safeRiwayah) }
        }
    }

    /// Reciters for the given riwayah that are enabled in the priority list (or not listed = enabled by default).
    private func enabledMatchingReciters(riwayah: Riwayah, settings s: PlaybackSettings) -> [Reciter] {
        matchingReciters(riwayah: riwayah).filter { r in
            (s.reciterPriority ?? []).first(where: { $0.reciterId == r.id })?.isEnabled ?? true
        }
    }

    /// Riwayat that have at least one enabled reciter.
    /// Falls back to all cases if the library is empty.
    private func availableRiwayat(for s: PlaybackSettings) -> [Riwayah] {
        let withEnabled = Riwayah.allCases.filter { r in !enabledMatchingReciters(riwayah: r, settings: s).isEmpty }
        guard !withEnabled.isEmpty else { return Riwayah.allCases }
        return withEnabled
    }

    /// If the current riwayah has no enabled reciters, auto-switch to the first one that does.
    private func snapReciterSelectionIfNeeded() {
        guard let s = settings else { return }
        let available = availableRiwayat(for: s)
        guard !available.contains(s.safeRiwayah), let first = available.first else { return }
        s.selectedRiwayah = first.rawValue
        // Clear specific reciter if it no longer has sources for the new riwayah
        if let id = s.selectedReciterId,
           !matchingReciters(riwayah: first).contains(where: { $0.id == id }) {
            s.selectedReciterId = nil
        }
        save()
    }

    // MARK: - Availability helpers

    /// Available ayahs for the currently selected reciter/riwayah.
    /// nil = no filtering (all available or availability unknown).
    private var availableAyahsForSelection: Set<AyahRef>? {
        guard let s = settings else { return nil }
        let targetRiwayah = s.safeRiwayah
        if let reciterId = s.selectedReciterId,
           let reciter = allReciters.first(where: { $0.id == reciterId }) {
            return availableAyahs(for: reciter, targetRiwayah: targetRiwayah)
        }
        // Auto mode: union of per-reciter available sets.
        // An ayah is available if at least ONE enabled reciter has it.
        let enabled = enabledMatchingReciters(riwayah: targetRiwayah, settings: s)
        guard !enabled.isEmpty else { return nil }
        let perReciterAvail = enabled.map { availableAyahs(for: $0, targetRiwayah: targetRiwayah) }
        // Any unknown (nil) reciter means we can't restrict.
        if perReciterAvail.contains(where: { $0 == nil }) { return nil }
        var union = Set<AyahRef>()
        union.reserveCapacity(6236)
        for case let avail? in perReciterAvail { union.formUnion(avail) }
        return union.isEmpty ? nil : union
    }

    /// Separate allowed sets for the FROM and TO pickers.
    /// For local-only reciters, returns segment start/end boundaries directly — no heuristics.
    /// For CDN/mixed reciters, uses the existing contiguous-block heuristic.
    private var allowedAyahRanges: (start: Set<AyahRef>?, end: Set<AyahRef>?) {
        guard let s = settings else { return (nil, nil) }

        // Specific local-only reciter — use segment boundaries for the selected riwayah
        if let id = s.selectedReciterId,
           let reciter = allReciters.first(where: { $0.id == id }),
           !reciter.hasCDN {
            guard let (starts, ends) = segmentBoundariesForLocalReciter(reciter, riwayah: s.safeRiwayah)
            else { return (nil, nil) }
            return (starts, ends)
        }

        // Auto mode where ALL enabled reciters are local-only
        if s.selectedReciterId == nil {
            let enabled = enabledMatchingReciters(riwayah: s.safeRiwayah, settings: s)
            if !enabled.isEmpty && enabled.allSatisfy({ !$0.hasCDN }) {
                var allStarts = Set<AyahRef>()
                var allEnds   = Set<AyahRef>()
                for reciter in enabled {
                    if let (st, en) = segmentBoundariesForLocalReciter(reciter, riwayah: s.safeRiwayah) {
                        allStarts.formUnion(st); allEnds.formUnion(en)
                    }
                }
                return allStarts.isEmpty ? (nil, nil) : (allStarts, allEnds)
            }
        }

        // CDN or mixed — use existing contiguous-block heuristics
        guard let available = availableAyahsForSelection else { return (nil, nil) }
        return (allowedStartAyahs(from: available), allowedEndAyahs(from: available))
    }

    /// Returns the start and end AyahRefs for each segment of a local reciter,
    /// filtered to the given riwayah. Returns nil if no matching segments exist.
    private func segmentBoundariesForLocalReciter(
        _ reciter: Reciter,
        riwayah: Riwayah
    ) -> (starts: Set<AyahRef>, ends: Set<AyahRef>)? {
        let segments = (reciter.segments ?? []).filter { seg in
            let segRiwayah = seg.safeRiwayah
            if segRiwayah == riwayah { return true }
            guard let ss = seg.surahNumber, let sa = seg.ayahNumber else { return false }
            let es = seg.endSurahNumber ?? ss
            let ea = seg.endAyahNumber ?? sa
            return isCompatibleAcrossRange(segRiwayah: segRiwayah, targetRiwayah: riwayah,
                                           from: AyahRef(surah: ss, ayah: sa),
                                           to: AyahRef(surah: es, ayah: ea))
        }
        guard !segments.isEmpty else { return nil }
        var starts = Set<AyahRef>()
        var ends   = Set<AyahRef>()
        for seg in segments {
            guard let ss = seg.surahNumber, let sa = seg.ayahNumber else { continue }
            starts.insert(AyahRef(surah: ss, ayah: sa))
            ends.insert(AyahRef(surah: seg.endSurahNumber ?? ss,
                                ayah: seg.endAyahNumber  ?? sa))
        }
        return starts.isEmpty ? nil : (starts, ends)
    }

    private func availableAyahs(for reciter: Reciter, targetRiwayah: Riwayah) -> Set<AyahRef>? {
        // Compute CDN availability (if applicable)
        let cdnAvail: Set<AyahRef>? = reciter.hasCDN ? cdnAvailableAyahs(for: reciter, targetRiwayah: targetRiwayah) : nil

        // Compute local/personal recording availability (if applicable)
        let localAvail: Set<AyahRef>? = reciter.hasPersonalRecordings ? availableAyahsForLocalReciter(reciter, targetRiwayah: targetRiwayah) : nil

        // Union: nil means full coverage (or unchecked CDN), so if either is nil, use the other
        switch (cdnAvail, localAvail) {
        case (nil, nil):
            return nil
        case (let avail?, nil):
            return avail
        case (nil, let avail?):
            return avail
        case (var cdn?, let local?):
            cdn.formUnion(local)
            return cdn.count >= 6236 ? nil : cdn
        }
    }

    /// CDN-only availability: returns the set of available ayahs from CDN sources,
    /// or nil if CDN has full coverage or hasn't been checked.
    private func cdnAvailableAyahs(for reciter: Reciter, targetRiwayah: Riwayah) -> Set<AyahRef>? {
        let sources = reciter.cdnSources ?? []
        guard !sources.isEmpty else { return nil }

        let checkedSources = sources.filter { $0.availabilityChecked }
        guard !checkedSources.isEmpty else { return nil }

        // For exact riwayah match, use that specific source's missing data
        if let exactSource = checkedSources.first(where: { $0.safeRiwayah == targetRiwayah }) {
            let missing = Set(exactSource.missingAyahs)
            guard !missing.isEmpty else { return nil }
            return buildAvailableSet(excluding: missing)
        }

        // No exact CDN source: build compatibility-filtered set using all sources
        let cdnRiwayaat = sources.compactMap { src -> Riwayah? in
            guard let raw = src.riwayah else { return nil }
            return Riwayah(rawValue: raw)
        }
        guard !cdnRiwayaat.isEmpty else { return nil }

        var allMissing = Set<AyahRef>()
        for src in checkedSources { allMissing.formUnion(src.missingAyahs) }

        let compat = RiwayahCompatibilityService.shared
        var filtered = Set<AyahRef>()
        filtered.reserveCapacity(6236)
        for surah in 1...114 {
            let count = metadata.ayahCount(surah: surah)
            for ayah in 1...max(1, count) {
                let ref = AyahRef(surah: surah, ayah: ayah)
                if allMissing.contains(ref) { continue }
                let compatibles = compat.compatibleRiwayaat(surah: surah, ayah: ayah, targetRiwayah: targetRiwayah)
                if cdnRiwayaat.contains(where: { compatibles.contains($0) }) {
                    filtered.insert(ref)
                }
            }
        }
        return filtered.isEmpty ? nil : filtered
    }

    /// Expands RecordingSegments for a local reciter into individual AyahRefs,
    /// restricted to segments whose riwayah is compatible with `targetRiwayah` across the full range.
    /// Returns nil if the reciter has no matching segments or covers all 6236 ayahs.
    private func availableAyahsForLocalReciter(_ reciter: Reciter, targetRiwayah: Riwayah) -> Set<AyahRef>? {
        let segments = (reciter.segments ?? []).filter { seg in
            let segRiwayah = seg.safeRiwayah
            if segRiwayah == targetRiwayah { return true }
            guard let ss = seg.surahNumber, let sa = seg.ayahNumber else { return false }
            let es = seg.endSurahNumber ?? ss
            let ea = seg.endAyahNumber ?? sa
            return isCompatibleAcrossRange(segRiwayah: segRiwayah, targetRiwayah: targetRiwayah,
                                           from: AyahRef(surah: ss, ayah: sa),
                                           to: AyahRef(surah: es, ayah: ea))
        }
        guard !segments.isEmpty else { return nil }
        var available = Set<AyahRef>()
        available.reserveCapacity(6236)
        for seg in segments {
            guard let ss = seg.surahNumber, let sa = seg.ayahNumber else { continue }
            let es = seg.endSurahNumber ?? ss
            let ea = seg.endAyahNumber ?? sa
            var current = AyahRef(surah: ss, ayah: sa)
            let end = AyahRef(surah: es, ayah: ea)
            while current <= end {
                available.insert(current)
                guard let next = nextAyah(after: current) else { break }
                current = next
            }
        }
        return available.count >= 6236 ? nil : available
    }

    /// True if the current From–To range contains at least one ayah that would be skipped
    /// (not covered by any available source for the selected riwayah).
    ///
    /// In Auto mode, computes the union of KNOWN per-reciter coverages. A CDN reciter with
    /// confirmed full coverage (availabilityChecked + no missing ayahs) suppresses the warning
    /// entirely. Unchecked CDN reciters contribute no known coverage — the warning may fire
    /// conservatively, but will not produce false negatives.
    private var rangeHasSkips: Bool {
        guard let s = settings else { return false }
        let targetRiwayah = s.safeRiwayah
        let rangeStart = AyahRef(surah: startSurah, ayah: startAyah)
        let rangeEnd   = AyahRef(surah: endSurah,   ayah: endAyah)

        // Specific reciter: straightforward.
        if let reciterId = s.selectedReciterId,
           let reciter = allReciters.first(where: { $0.id == reciterId }) {
            guard let coverage = availableAyahs(for: reciter, targetRiwayah: targetRiwayah)
            else { return false }
            return rangeContainsGap(coverage, from: rangeStart, to: rangeEnd)
        }

        // Auto mode: build union of KNOWN (non-nil) per-reciter coverages.
        // If any reciter has confirmed full coverage, no skip is possible — suppress.
        // Unchecked CDN reciters are unknown — don't count as coverage.
        let enabled = enabledMatchingReciters(riwayah: targetRiwayah, settings: s)
        guard !enabled.isEmpty else { return false }

        var known = Set<AyahRef>()
        known.reserveCapacity(6236)
        for reciter in enabled {
            if let avail = availableAyahs(for: reciter, targetRiwayah: targetRiwayah) {
                known.formUnion(avail)
            } else if isConfirmedFullCoverage(reciter, targetRiwayah: targetRiwayah) {
                return false   // guaranteed coverage → no skips possible
            }
            // nil from unchecked/incompatible CDN: unknown — omit from union
        }
        guard !known.isEmpty else { return false }   // all unknowns → can't determine
        return rangeContainsGap(known, from: rangeStart, to: rangeEnd)
    }

    private func rangeContainsGap(_ coverage: Set<AyahRef>, from start: AyahRef, to end: AyahRef) -> Bool {
        var cur = start
        while cur <= end {
            if !coverage.contains(cur) { return true }
            guard let next = nextAyah(after: cur) else { break }
            cur = next
        }
        return false
    }

    /// Returns true when a CDN reciter is known to provide gapless coverage for targetRiwayah.
    private func isConfirmedFullCoverage(_ reciter: Reciter, targetRiwayah: Riwayah) -> Bool {
        guard reciter.hasCDN else { return false }
        guard let source = (reciter.cdnSources ?? []).first(where: {
            $0.safeRiwayah == targetRiwayah
        }) else { return false }
        return source.availabilityChecked && source.missingAyahs.isEmpty
    }

    /// True if all ayahs in the preset's range are in the available set.
    private func isPresetFullyAvailable(_ preset: Preset) -> Bool {
        guard let allowed = availableAyahsForSelection else { return true }
        var current = preset.range.start
        while current <= preset.range.end {
            if !allowed.contains(current) { return false }
            guard let next = nextAyah(after: current) else { break }
            current = next
        }
        return true
    }

    private func buildAvailableSet(excluding missing: Set<AyahRef>) -> Set<AyahRef> {
        var available = Set<AyahRef>()
        available.reserveCapacity(6236)
        for surah in 1...114 {
            let count = metadata.ayahCount(surah: surah)
            for ayah in 1...max(1, count) {
                let ref = AyahRef(surah: surah, ayah: ayah)
                if !missing.contains(ref) { available.insert(ref) }
            }
        }
        return available
    }

    // MARK: - Range compatibility helper

    private func isCompatibleAcrossRange(segRiwayah: Riwayah,
                                          targetRiwayah: Riwayah,
                                          from start: AyahRef,
                                          to end: AyahRef) -> Bool {
        let compat = RiwayahCompatibilityService.shared
        var current = start
        while current <= end {
            let compatibles = compat.compatibleRiwayaat(surah: current.surah, ayah: current.ayah, targetRiwayah: targetRiwayah)
            if !compatibles.contains(segRiwayah) { return false }
            guard let next = nextAyah(after: current) else { break }
            current = next
        }
        return true
    }

    // MARK: - Sequential ayah navigation

    private func nextAyah(after ref: AyahRef) -> AyahRef? {
        let count = metadata.ayahCount(surah: ref.surah)
        if ref.ayah < count { return AyahRef(surah: ref.surah, ayah: ref.ayah + 1) }
        if ref.surah < 114 { return AyahRef(surah: ref.surah + 1, ayah: 1) }
        return nil
    }

    private func previousAyah(before ref: AyahRef) -> AyahRef? {
        if ref.ayah > 1 { return AyahRef(surah: ref.surah, ayah: ref.ayah - 1) }
        if ref.surah > 1 {
            let prev = ref.surah - 1
            return AyahRef(surah: prev, ayah: metadata.ayahCount(surah: prev))
        }
        return nil
    }

    /// Valid START ayahs: next sequential is available, OR isolated (single-ayah segment).
    private func allowedStartAyahs(from available: Set<AyahRef>) -> Set<AyahRef> {
        available.filter { ref in
            let nextAvail = nextAyah(after: ref).map { available.contains($0) } ?? false
            if nextAvail { return true }
            // Isolated: no available neighbor in either direction
            let prevAvail = previousAyah(before: ref).map { available.contains($0) } ?? false
            return !prevAvail
        }
    }

    /// Valid END ayahs: previous sequential is available, OR isolated.
    private func allowedEndAyahs(from available: Set<AyahRef>) -> Set<AyahRef> {
        available.filter { ref in
            let prevAvail = previousAyah(before: ref).map { available.contains($0) } ?? false
            if prevAvail { return true }
            let nextAvail = nextAyah(after: ref).map { available.contains($0) } ?? false
            return !nextAvail
        }
    }

    /// Triggers CDN availability checks for any unchecked CDN reciters in the current selection.
    /// Runs in the background; updates FROM/TO pickers via @Query refresh when complete.
    private func triggerAvailabilityChecksIfNeeded() {
        guard !isCheckingAvailability, let s = settings else { return }
        let targetRiwayah = s.safeRiwayah

        let hasUncheckedSources: (Reciter) -> Bool = { r in
            r.hasCDN && (r.cdnSources ?? []).contains { !$0.availabilityChecked }
        }

        var toCheck: [Reciter]
        if let reciterId = s.selectedReciterId,
           let reciter = allReciters.first(where: { $0.id == reciterId }),
           hasUncheckedSources(reciter) {
            toCheck = [reciter]
        } else if s.selectedReciterId == nil {
            toCheck = enabledMatchingReciters(riwayah: targetRiwayah, settings: s)
                .filter { hasUncheckedSources($0) }
        } else {
            return
        }
        guard !toCheck.isEmpty else { return }

        isCheckingAvailability = true
        Task {
            defer { isCheckingAvailability = false }
            for reciter in toCheck {
                for source in (reciter.cdnSources ?? []) where !source.availabilityChecked {
                    let missing = await CDNAvailabilityChecker.shared.findMissingAyahs(
                        reciter: reciter, source: source, progress: { _ in })
                    guard let data = try? JSONEncoder().encode(missing),
                          let json = String(data: data, encoding: .utf8) else { continue }
                    source.missingAyahsJSON = json
                    try? context.save()
                }
            }
            snapRangeToAvailableIfNeeded()
        }
    }

    /// Snaps start/end to valid allowed ayahs when reciter changes.
    private func snapRangeToAvailableIfNeeded() {
        let (allowedStart, allowedEnd) = allowedAyahRanges
        if let allowed = allowedStart, !allowed.contains(AyahRef(surah: startSurah, ayah: startAyah)) {
            if let first = allowed.sorted().first {
                startSurah = first.surah; startAyah = first.ayah
            }
        }
        if let allowed = allowedEnd, !allowed.contains(AyahRef(surah: endSurah, ayah: endAyah)) {
            if let last = allowed.sorted().last {
                endSurah = last.surah; endAyah = last.ayah
            }
        }
        clampEndIfNeeded()
    }

    private func showAfterRepeat(_ s: PlaybackSettings) -> Bool {
        guard (s.rangeRepeatCount ?? 1) != -1 else { return false }
        if let id = s.selectedReciterId, let reciter = allReciters.first(where: { $0.id == id }) {
            // Local-only reciter: enable continuation only if fully annotated (all 6236 ayahs)
            if !reciter.hasCDN {
                return reciter.hasPersonalRecordings && availableAyahsForLocalReciter(reciter, targetRiwayah: s.safeRiwayah) == nil
            }
            return reciter.hasCDN
        }
        let riwayah = s.safeRiwayah
        return allReciters.contains { r in
            r.hasCDN && (r.cdnSources ?? []).contains { Riwayah(rawValue: $0.riwayah ?? "") == riwayah }
        }
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
        // Compute covered ayahs here on the main actor, where @Query-loaded model objects are
        // live. Passing this into the engine avoids silent lazy-load failures that occur when
        // SwiftData relationships are accessed off the main-actor context.
        let coveredAyahs = coveredAyahsForPlayback(settings: s)
        let capturedPlayback = playback
        let capturedContext  = context
        let isSlidingWindow = s.safeSlidingWindowEnabled
        dismiss()

        if isSlidingWindow {
            Task { await capturedPlayback.playSlidingWindow(range: range, settings: s,
                                                            context: capturedContext,
                                                            coveredAyahs: coveredAyahs) }
        } else {
            // If "After Repeating" is hidden, the user can't change it — force it to disabled.
            if !showAfterRepeat(s) {
                s.afterRepeatAction = AfterRepeatAction.stop.rawValue
            }
            Task { await capturedPlayback.play(range: range, settings: s, context: capturedContext,
                                               coveredAyahs: coveredAyahs) }
        }
    }

    /// Expands all segment ranges for the active local-only reciter selection into a flat set
    /// of ayah refs (filtered to the selected riwayah). Returns nil for CDN/mixed sessions.
    private func coveredAyahsForPlayback(settings s: PlaybackSettings) -> Set<AyahRef>? {
        let riwayah = s.safeRiwayah

        // Specific local-only reciter
        if let id = s.selectedReciterId,
           let reciter = allReciters.first(where: { $0.id == id }),
           !reciter.hasCDN {
            return expandSegments(of: reciter, riwayah: riwayah)
        }

        // Auto mode — only when ALL enabled reciters are local-only
        let enabled = enabledMatchingReciters(riwayah: riwayah, settings: s)
        guard !enabled.isEmpty && enabled.allSatisfy({ !$0.hasCDN }) else { return nil }
        var union = Set<AyahRef>()
        union.reserveCapacity(6236)
        for reciter in enabled {
            if let avail = expandSegments(of: reciter, riwayah: riwayah) {
                union.formUnion(avail)
            }
        }
        return union.isEmpty ? nil : union
    }

    /// Expands segments of a reciter compatible with `riwayah` into a flat AyahRef set.
    private func expandSegments(of reciter: Reciter, riwayah: Riwayah) -> Set<AyahRef>? {
        let segments = (reciter.segments ?? []).filter { seg in
            let segRiwayah = seg.safeRiwayah
            if segRiwayah == riwayah { return true }
            guard let ss = seg.surahNumber, let sa = seg.ayahNumber else { return false }
            let es = seg.endSurahNumber ?? ss
            let ea = seg.endAyahNumber ?? sa
            return isCompatibleAcrossRange(segRiwayah: segRiwayah, targetRiwayah: riwayah,
                                           from: AyahRef(surah: ss, ayah: sa),
                                           to: AyahRef(surah: es, ayah: ea))
        }
        guard !segments.isEmpty else { return nil }
        var covered = Set<AyahRef>()
        for seg in segments {
            guard let ss = seg.surahNumber, let sa = seg.ayahNumber else { continue }
            let es = seg.endSurahNumber ?? ss
            let ea = seg.endAyahNumber  ?? sa
            var cur = AyahRef(surah: ss, ayah: sa)
            let end = AyahRef(surah: es, ayah: ea)
            while cur <= end {
                covered.insert(cur)
                guard let next = nextAyah(after: cur) else { break }
                cur = next
            }
        }
        return covered.isEmpty ? nil : covered
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

    private func rangeRepeatBehaviorBinding(_ s: PlaybackSettings) -> Binding<RangeRepeatBehavior> {
        Binding(
            get: { s.safeRangeRepeatBehavior },
            set: { s.rangeRepeatBehavior = $0.rawValue; save() }
        )
    }

    private func showRangeRepeatBehavior(_ s: PlaybackSettings) -> Bool {
        s.safeAyahRepeat != 1 && s.safeRangeRepeat != 1
    }

    private func afterRepeatBinding(_ s: PlaybackSettings) -> Binding<AfterRepeatOption> {
        Binding(
            get: { .from(s) },
            set: { $0.apply(to: s); save() }
        )
    }

    private func slidingWindowEnabledBinding(_ s: PlaybackSettings) -> Binding<Bool> {
        Binding(get: { s.safeSlidingWindowEnabled }, set: { s.slidingWindowEnabled = $0; save() })
    }

    private func swPerAyahBinding(_ s: PlaybackSettings) -> Binding<Int> {
        Binding(get: { s.safeSWPerAyahRepeats }, set: { s.slidingWindowPerAyahRepeats = $0; save() })
    }

    private func swConnectionRepeatsBinding(_ s: PlaybackSettings) -> Binding<Int> {
        Binding(get: { s.safeSWConnectionRepeats }, set: { s.slidingWindowConnectionRepeats = $0; save() })
    }

    private func swConnectionWindowBinding(_ s: PlaybackSettings) -> Binding<Int> {
        Binding(get: { s.safeSWConnectionWindow }, set: { s.slidingWindowConnectionWindow = $0; save() })
    }

    private func swFullRangeBinding(_ s: PlaybackSettings) -> Binding<Int> {
        Binding(get: { s.safeSWFullRangeRepeats }, set: { s.slidingWindowFullRangeRepeats = $0; save() })
    }

    private func save() { try? context.save() }

    // MARK: - Estimated duration

    private var estimateInputs: EstimateInputs {
        let s = settings
        return EstimateInputs(
            startSurah: startSurah, startAyah: startAyah,
            endSurah: endSurah, endAyah: endAyah,
            speed: s?.safeSpeed ?? 1.0,
            gapMs: s?.safeGapMs ?? 0,
            ayahRepeat: s?.safeAyahRepeat ?? 1,
            rangeRepeat: s?.safeRangeRepeat ?? 1,
            slidingWindow: s?.safeSlidingWindowEnabled ?? false,
            swA: s?.safeSWPerAyahRepeats ?? 5,
            swB: s?.safeSWConnectionRepeats ?? 3,
            swC: s?.safeSWConnectionWindow ?? 2,
            swD: s?.safeSWFullRangeRepeats ?? 10,
            reciterId: s?.selectedReciterId,
            riwayah: s?.safeRiwayah ?? .hafs
        )
    }

    private var estimatedTimeLabel: String {
        if estimateIsInfinite { return "Estimated time: ∞" }
        guard let duration = estimatedDuration else { return " " }
        return "Estimated time: ~\(formatDuration(duration))"
    }

    private func computeEstimatedDuration() async {
        guard let s = settings else { return }

        let ayahRepeat = s.safeAyahRepeat
        let rangeRepeat = s.safeRangeRepeat
        let isSW = s.safeSlidingWindowEnabled

        // Infinite check
        if !isSW && (ayahRepeat == -1 || rangeRepeat == -1) {
            estimateIsInfinite = true
            estimatedDuration = nil
            return
        }
        estimateIsInfinite = false

        let speed = s.safeSpeed
        let gapSeconds = Double(s.safeGapMs) / 1000.0

        // Build ayah list
        var ayahs: [AyahRef] = []
        var cursor = AyahRef(surah: startSurah, ayah: startAyah)
        let end = AyahRef(surah: endSurah, ayah: endAyah)
        while cursor <= end {
            ayahs.append(cursor)
            guard let next = nextAyah(after: cursor) else { break }
            cursor = next
        }
        guard !ayahs.isEmpty else {
            estimatedDuration = nil
            return
        }

        // Resolve durations
        let durations = await loadAyahDurations(ayahs: ayahs, settings: s)
        let n = durations.count
        guard n > 0 else { estimatedDuration = nil; return }

        try? Task.checkCancellation()

        let totalDuration: TimeInterval
        if isSW {
            let swA = s.safeSWPerAyahRepeats
            let swB = s.safeSWConnectionRepeats
            let swC = s.safeSWConnectionWindow
            let swD = s.safeSWFullRangeRepeats
            let fullRangeSum = durations.reduce(0, +)

            var soloTime = 0.0
            for d in durations { soloTime += d * Double(swA) }

            var connectionTime = 0.0
            for i in 1..<n {
                let windowStart = max(0, i - swC)
                let windowSum = durations[windowStart...i].reduce(0, +)
                connectionTime += windowSum * Double(swB)
            }

            let fullTime = fullRangeSum * Double(swD)
            totalDuration = (soloTime + connectionTime + fullTime) / speed
        } else {
            let sumDurations = durations.reduce(0, +)
            let perPassAudio = sumDurations * Double(ayahRepeat)
            let perPassGaps = Double(n * ayahRepeat - 1) * gapSeconds
            let onePass = (perPassAudio + perPassGaps) / speed
            totalDuration = onePass * Double(rangeRepeat)
        }

        estimatedDuration = totalDuration
    }

    private func loadAyahDurations(ayahs: [AyahRef], settings s: PlaybackSettings) async -> [Double] {
        let fallbackDuration = 6.0
        let riwayah = s.safeRiwayah
        let cache = AudioFileCache.shared

        // Determine the effective reciter
        let reciter: Reciter?
        if let id = s.selectedReciterId {
            reciter = allReciters.first { $0.id == id }
        } else {
            reciter = enabledMatchingReciters(riwayah: riwayah, settings: s).first
        }
        guard let reciter else { return ayahs.map { _ in fallbackDuration } }

        // For CDN reciters, find the best matching source
        let cdnSource: ReciterCDNSource? = (reciter.cdnSources ?? []).first { $0.safeRiwayah == riwayah }
            ?? (reciter.cdnSources ?? []).first

        // Pre-compute local file URLs on the main actor (SwiftData models aren't Sendable)
        var cdnFileURLs: [AyahRef: URL] = [:]
        if let source = cdnSource {
            for ref in ayahs {
                let url = await cache.localFileURL(for: ref, reciter: reciter, source: source)
                if FileManager.default.fileExists(atPath: url.path) {
                    cdnFileURLs[ref] = url
                }
            }
        }

        // For local recordings, build a lookup of segment durations (no file I/O needed)
        var segmentDurations: [AyahRef: Double] = [:]
        if reciter.hasPersonalRecordings {
            for seg in reciter.segments ?? [] {
                guard seg.safeRiwayah == riwayah || RiwayahCompatibilityService.shared
                    .everCompatible(with: riwayah).contains(seg.safeRiwayah) else { continue }
                let ref = seg.primaryAyahRef
                let endRef = seg.endAyahRef
                let dur = seg.safeDuration
                guard dur > 0 else { continue }
                // For multi-ayah segments, distribute duration evenly
                var count = 0
                var cur = ref
                while cur <= endRef {
                    count += 1
                    guard let next = nextAyah(after: cur) else { break }
                    cur = next
                }
                let perAyah = dur / Double(max(1, count))
                cur = ref
                while cur <= endRef {
                    segmentDurations[cur] = perAyah
                    guard let next = nextAyah(after: cur) else { break }
                    cur = next
                }
            }
        }

        // Load durations in parallel — only plain values (URLs, Doubles) cross into tasks
        return await withTaskGroup(of: (Int, Double).self, returning: [Double].self) { group in
            for (index, ref) in ayahs.enumerated() {
                let segDur = segmentDurations[ref]
                let fileURL = cdnFileURLs[ref]
                group.addTask {
                    // Prefer local segment duration (no I/O needed)
                    if let dur = segDur, dur > 0 { return (index, dur) }
                    // Load duration from cached CDN file
                    if let url = fileURL,
                       let dur = await cache.audioDuration(url: url), dur > 0 {
                        return (index, dur)
                    }
                    return (index, fallbackDuration)
                }
            }
            var results = [Double](repeating: fallbackDuration, count: ayahs.count)
            for await (index, duration) in group {
                results[index] = duration
            }
            return results
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else if minutes > 0 {
            return secs > 0 ? "\(minutes)m \(secs)s" : "\(minutes)m"
        } else {
            return "\(secs)s"
        }
    }
}

private struct EstimateInputs: Equatable, Hashable {
    let startSurah: Int, startAyah: Int, endSurah: Int, endAyah: Int
    let speed: Double, gapMs: Int, ayahRepeat: Int, rangeRepeat: Int
    let slidingWindow: Bool, swA: Int, swB: Int, swC: Int, swD: Int
    let reciterId: UUID?
    let riwayah: Riwayah
}
