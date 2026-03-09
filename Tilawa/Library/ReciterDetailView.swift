import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Data model

private enum ReciterSourceKind {
    case recording(Recording, AyahRange)
    case cdnSource(ReciterCDNSource)
}

private struct ReciterSourceItem: Identifiable {
    let id: String
    let kind: ReciterSourceKind
    let segments: [RecordingSegment]   // populated for .recording, empty for CDN
    var explicitOrder: Int?
    var occurrence: Int?               // nil = unique range, 1/2/3… = Nth duplicate range
}

// MARK: - Lightweight preview player (scoped to this screen)

@Observable
@MainActor
private final class SegmentPreviewPlayer {
    var playingItemId: String?

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var endTime: Double?

    func play(recording: Recording, segments: [RecordingSegment], itemId: String) {
        stop()
        guard let path = recording.storagePath else { return }
        let url = AudioImporter.recordingsDirectory.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let sortedSegs = segments.sorted { ($0.startOffsetSeconds ?? 0) < ($1.startOffsetSeconds ?? 0) }
        let startTime = sortedSegs.first?.startOffsetSeconds ?? 0
        let endTimeVal = sortedSegs.last?.endOffsetSeconds ?? recording.safeDuration

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.currentTime = startTime
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            playingItemId = itemId
            endTime = endTimeVal

            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let player = self.audioPlayer else { return }
                    let pastEnd = self.endTime.map { player.currentTime >= $0 } ?? false
                    if !player.isPlaying || pastEnd { self.stop() }
                }
            }
        } catch {
            playingItemId = nil
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        timer?.invalidate()
        timer = nil
        endTime = nil
        playingItemId = nil
    }
}

// MARK: - View

struct ReciterDetailView: View {

    let reciter: Reciter

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var allSegments: [RecordingSegment]

    @State private var sources: [ReciterSourceItem] = []
    @State private var showAddCDNSource = false
    @State private var cacheSize: Int64 = 0
    @State private var previewPlayer = SegmentPreviewPlayer()

    private var reciterSegments: [RecordingSegment] {
        allSegments.filter { $0.reciter?.id == reciter.id }
    }

    var body: some View {
        List {
            let riwayahSummary = reciter.riwayahSummary
            if !riwayahSummary.isEmpty {
                Section("Riwayaat") {
                    ForEach(riwayahSummary, id: \.riwayah) { entry in
                        HStack {
                            Text(entry.riwayah.displayName)
                            Spacer()
                            if entry.segmentCount > 0 {
                                Text("\(entry.segmentCount) segments")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if reciter.hasCDN && (reciter.cdnSources ?? []).contains(where: { $0.riwayah.flatMap(Riwayah.init) == entry.riwayah }) {
                                Label("CDN", systemImage: "icloud")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                }
            }

            Section {
                if sources.isEmpty {
                    Text("No audio sources")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sources) { item in
                        sourceRow(item)
                    }
                    .onMove { from, to in
                        sources.move(fromOffsets: from, toOffset: to)
                        saveOrder()
                    }
                }
                Button {
                    showAddCDNSource = true
                } label: {
                    Label("Add CDN Source", systemImage: "plus.circle")
                }
            } header: {
                Text("Playback Priority")
            } footer: {
                Text("Drag to reorder. The topmost source is tried first during playback.")
                    .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(reciter.safeName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { buildSources() }
        .onDisappear { previewPlayer.stop() }
        .task { cacheSize = await AudioFileCache.shared.cacheSize(for: reciter) }
        .onChange(of: reciterSegments.count) { _, _ in buildSources() }
        .sheet(isPresented: $showAddCDNSource, onDismiss: buildSources) {
            ManifestImportView(targetReciter: reciter)
        }
    }

    // MARK: - Source row

    @ViewBuilder
    private func sourceRow(_ item: ReciterSourceItem) -> some View {
        switch item.kind {
        case .recording(let recording, let range):
            recordingRow(itemId: item.id, recording: recording, range: range, segments: item.segments, occurrence: item.occurrence)
        case .cdnSource(let source):
            NavigationLink {
                SurahDownloadSelectorView(reciter: reciter, source: source)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    let label = source.urlTemplate != nil ? "CDN · url template" : "CDN · manifest"
                    Label(label, systemImage: "icloud")
                        .font(.body)
                    if let riwayah = source.riwayah.flatMap(Riwayah.init) {
                        Text(riwayah.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let preview = source.urlTemplate ?? source.baseURL ?? ""
                    if !preview.isEmpty {
                        Text(String(preview.prefix(40)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deleteCDNSource(source)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func recordingRow(itemId: String, recording: Recording, range: AyahRange, segments: [RecordingSegment], occurrence: Int? = nil) -> some View {
        let meta = QuranMetadataService.shared
        let start = range.start
        let end = range.end

        let rangeLabel: String
        if start.surah == end.surah {
            rangeLabel = "\(meta.surahName(start.surah)) \(start.surah):\(start.ayah)–\(end.ayah)"
        } else {
            rangeLabel = "\(meta.surahName(start.surah)) \(start.surah):\(start.ayah) – \(meta.surahName(end.surah)) \(end.surah):\(end.ayah)"
        }

        var subtitleParts: [String] = []
        if let fmt = recording.fileFormat { subtitleParts.append(fmt) }
        if let date = recording.importedAt {
            let f = DateFormatter()
            f.dateFormat = "MMM d, yyyy"
            subtitleParts.append(f.string(from: date))
        }
        let subtitle = subtitleParts.joined(separator: " · ")

        let isPlaying = previewPlayer.playingItemId == itemId

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(rangeLabel)
                    if let occ = occurrence {
                        Text("\(occ)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.secondary, in: Circle())
                    }
                }
                .font(.body)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                if isPlaying {
                    previewPlayer.stop()
                } else {
                    previewPlayer.play(recording: recording, segments: segments, itemId: itemId)
                }
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isPlaying ? .red : Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }


    // MARK: - Build sources

    private func buildSources() {
        var items: [ReciterSourceItem] = []
        let meta = QuranMetadataService.shared

        // Group segments by recording
        var byRecording: [UUID: (recording: Recording, segs: [RecordingSegment])] = [:]
        for seg in reciterSegments {
            guard let rec = seg.recording, let recId = rec.id else { continue }
            if byRecording[recId] == nil { byRecording[recId] = (rec, []) }
            byRecording[recId]!.segs.append(seg)
        }

        for (_, pair) in byRecording {
            // Build typed tuples so we can sort and group by ayah position
            typealias SegTuple = (seg: RecordingSegment, startRef: AyahRef, endRef: AyahRef)
            let typed: [SegTuple] = pair.segs.compactMap { seg in
                guard let s = seg.surahNumber, let a = seg.ayahNumber else { return nil }
                let startRef = AyahRef(surah: s, ayah: a)
                let es = seg.endSurahNumber ?? s
                let ea = seg.endAyahNumber  ?? a
                let endRef = AyahRef(surah: es, ayah: ea)
                return (seg, startRef, endRef)
            }.sorted { $0.startRef < $1.startRef }

            guard !typed.isEmpty else { continue }

            // Split into contiguous runs (consecutive ayahs, no gap)
            var runs: [[SegTuple]] = []
            var currentRun: [SegTuple] = [typed[0]]
            for i in 1..<typed.count {
                let prevEnd = typed[i - 1].endRef
                let currStart = typed[i].startRef
                if meta.ayah(after: prevEnd) == currStart {
                    currentRun.append(typed[i])
                } else {
                    runs.append(currentRun)
                    currentRun = [typed[i]]
                }
            }
            runs.append(currentRun)

            // One source item per contiguous run
            let recIdStr = pair.recording.id?.uuidString ?? UUID().uuidString
            for (runIdx, run) in runs.enumerated() {
                let rangeStart = run.first!.startRef
                let rangeEnd   = run.last!.endRef
                let range = AyahRange(start: rangeStart, end: rangeEnd)
                let segs  = run.map(\.seg)
                let itemId = "rec-\(recIdStr)-\(runIdx)"
                let order  = segs.compactMap(\.userSortOrder).min()
                items.append(ReciterSourceItem(
                    id: itemId,
                    kind: .recording(pair.recording, range),
                    segments: segs,
                    explicitOrder: order
                ))
            }
        }

        for source in reciter.cdnSources ?? [] {
            let itemId = "cdn-\(source.id?.uuidString ?? UUID().uuidString)"
            items.append(ReciterSourceItem(
                id: itemId,
                kind: .cdnSource(source),
                segments: [],
                explicitOrder: source.sortOrder
            ))
        }

        // Detect duplicate-range recording items and assign occurrence numbers
        var rangeKeys: [String: [Int]] = [:]  // key → indices of items with that range
        for (i, item) in items.enumerated() {
            if case .recording(let rec, let range) = item.kind {
                let key = "\(rec.id?.uuidString ?? "")-\(range.start.surah)-\(range.start.ayah)-\(range.end.surah)-\(range.end.ayah)"
                rangeKeys[key, default: []].append(i)
            }
        }
        for (_, indices) in rangeKeys where indices.count > 1 {
            for (occ, idx) in indices.enumerated() {
                items[idx].occurrence = occ + 1
            }
        }

        items.sort { lhs, rhs in
            switch (lhs.explicitOrder, rhs.explicitOrder) {
            case let (.some(lo), .some(ro)) where lo != ro: return lo < ro
            case (.some, nil): return true
            case (nil, .some): return false
            default: return tiebreakerIndex(lhs) < tiebreakerIndex(rhs)
            }
        }

        sources = items
    }

    private func tiebreakerIndex(_ item: ReciterSourceItem) -> Int {
        switch item.kind {
        case .recording:              return 0
        case .cdnSource(let source):  return source.urlTemplate != nil ? 2 : 1
        }
    }

    // MARK: - Delete CDN source

    private func deleteCDNSource(_ source: ReciterCDNSource) {
        reciter.cdnSources = (reciter.cdnSources ?? []).filter { $0.id != source.id }
        context.delete(source)

        // Clear cached audio for this reciter
        Task {
            try? await AudioFileCache.shared.deleteCache(for: reciter)
        }
        reciter.downloadedSurahsJSON = nil
        reciter.isDownloaded = false

        // If the reciter is now an orphan (no CDN, no personal recordings), delete it and go back
        if (reciter.cdnSources ?? []).isEmpty && !reciter.hasPersonalRecordings {
            if let id = reciter.id {
                PlaybackSettings.cleanupPriorityEntries(for: id, in: context)
            }
            context.delete(reciter)
            try? context.save()
            dismiss()
            return
        }
        try? context.save()
        buildSources()
    }

    // MARK: - Save

    private func saveOrder() {
        for (index, item) in sources.enumerated() {
            switch item.kind {
            case .recording:
                for seg in item.segments { seg.userSortOrder = index }
            case .cdnSource(let source):
                source.sortOrder = index
            }
        }
        try? context.save()
    }
}
