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
                        Text("page +1").tag(-101)
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

        // Current page + 1 ayah — current page plus the first ayah of the next page
        if let pageRange = mushafVM.currentPageAyahRange,
           let nextAyah = metadata.ayah(after: pageRange.last) {
            result.append(Preset(
                label: "pg \(page) +1",
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
        // Local-only reciter: derive from annotated RecordingSegments
        if !reciter.hasCDN {
            return reciter.hasPersonalRecordings ? availableAyahsForLocalReciter(reciter, targetRiwayah: targetRiwayah) : nil
        }
        // CDN reciter: use pre-computed availability check
        guard reciter.availabilityChecked else { return nil }
        let missing = Set(reciter.missingAyahs)

        let cdnRiwayaat = (reciter.cdnSources ?? []).compactMap { src -> Riwayah? in
            guard let raw = src.riwayah else { return nil }
            return Riwayah(rawValue: raw)
        }

        // Exact CDN source for targetRiwayah: standard behavior (nil = full coverage).
        if cdnRiwayaat.contains(targetRiwayah) {
            guard !missing.isEmpty else { return nil }
            return buildAvailableSet(excluding: missing)
        }

        // No exact CDN source: build compatibility-filtered set.
        guard !cdnRiwayaat.isEmpty else { return nil }
        let compat = RiwayahCompatibilityService.shared
        var filtered = Set<AyahRef>()
        filtered.reserveCapacity(6236)
        for surah in 1...114 {
            let count = metadata.ayahCount(surah: surah)
            for ayah in 1...max(1, count) {
                let ref = AyahRef(surah: surah, ayah: ayah)
                if missing.contains(ref) { continue }
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
        guard reciter.hasCDN && reciter.availabilityChecked else { return false }
        let cdnRiwayaat = (reciter.cdnSources ?? []).compactMap { Riwayah(rawValue: $0.riwayah ?? "") }
        return cdnRiwayaat.contains(targetRiwayah) && Set(reciter.missingAyahs).isEmpty
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

        var toCheck: [Reciter]
        if let reciterId = s.selectedReciterId,
           let reciter = allReciters.first(where: { $0.id == reciterId }),
           reciter.hasCDN && !reciter.availabilityChecked {
            toCheck = [reciter]
        } else if s.selectedReciterId == nil {
            toCheck = enabledMatchingReciters(riwayah: targetRiwayah, settings: s)
                .filter { $0.hasCDN && !$0.availabilityChecked }
        } else {
            return
        }
        guard !toCheck.isEmpty else { return }

        isCheckingAvailability = true
        Task {
            defer { isCheckingAvailability = false }
            for reciter in toCheck {
                let missing = await CDNAvailabilityChecker.shared.findMissingAyahs(
                    reciter: reciter, source: nil, progress: { _ in })
                guard let data = try? JSONEncoder().encode(missing),
                      let json = String(data: data, encoding: .utf8) else { continue }
                reciter.missingAyahsJSON = json
                try? context.save()
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
        // If "After Repeating" is hidden, the user can't change it — force it to disabled.
        if !showAfterRepeat(s) {
            s.afterRepeatAction = AfterRepeatAction.stop.rawValue
        }
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
        dismiss()
        Task { await capturedPlayback.play(range: range, settings: s, context: capturedContext,
                                           coveredAyahs: coveredAyahs) }
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

    /// Encodes afterRepeatAction + count into a single Int tag for the picker.
    /// 0 = stop, 3/5/10 = continueAyaat with that count, -100 = continuePages(1), -101 = continuePages(1)+extraAyah
    private func afterRepeatBinding(_ s: PlaybackSettings) -> Binding<Int> {
        Binding(
            get: {
                switch s.safeAfterRepeatAction {
                case .stop:           return 0
                case .continueAyaat:  return s.afterRepeatContinueAyaatCount ?? 3
                case .continuePages:  return (s.afterRepeatContinuePagesExtraAyah == true) ? -101 : -100
                }
            },
            set: { tag in
                switch tag {
                case 0:
                    s.afterRepeatAction = AfterRepeatAction.stop.rawValue
                    s.afterRepeatContinuePagesExtraAyah = false
                case -100:
                    s.afterRepeatAction = AfterRepeatAction.continuePages.rawValue
                    s.afterRepeatContinuePagesCount = 1
                    s.afterRepeatContinuePagesExtraAyah = false
                case -101:
                    s.afterRepeatAction = AfterRepeatAction.continuePages.rawValue
                    s.afterRepeatContinuePagesCount = 1
                    s.afterRepeatContinuePagesExtraAyah = true
                default:
                    s.afterRepeatAction = AfterRepeatAction.continueAyaat.rawValue
                    s.afterRepeatContinueAyaatCount = tag
                    s.afterRepeatContinuePagesExtraAyah = false
                }
                save()
            }
        )
    }

    private func save() { try? context.save() }
}
