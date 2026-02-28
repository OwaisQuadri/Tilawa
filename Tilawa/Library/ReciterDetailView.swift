import SwiftUI
import SwiftData

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
}

// MARK: - View

struct ReciterDetailView: View {

    let reciter: Reciter

    @Environment(\.modelContext) private var context
    @Environment(PlaybackViewModel.self) private var playbackVM

    @Query private var allSegments: [RecordingSegment]

    @State private var sources: [ReciterSourceItem] = []
    @State private var savedSourceOrder: [String] = []

    private var reciterSegments: [RecordingSegment] {
        allSegments.filter { $0.recording?.reciter?.id == reciter.id }
    }

    private var hasUnsavedChanges: Bool {
        sources.map(\.id) != savedSourceOrder
    }

    var body: some View {
        List {
            if reciter.hasCDN {
                Section {
                    NavigationLink {
                        SurahDownloadSelectorView(reciter: reciter, source: reciter.cdnSources?.first)
                    } label: {
                        Label("Download / Manage Surahs", systemImage: "arrow.down.circle")
                    }
                }
            }

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
                    }
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { saveOrder() }
                    .fontWeight(.semibold)
                    .disabled(!hasUnsavedChanges)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .onAppear { buildSources() }
        .onChange(of: reciterSegments.count) { _, _ in buildSources() }
    }

    // MARK: - Source row

    @ViewBuilder
    private func sourceRow(_ item: ReciterSourceItem) -> some View {
        switch item.kind {
        case .recording(let recording, let range):
            recordingRow(recording: recording, range: range, segments: item.segments)
        case .cdnSource(let source):
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
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deleteCDNSource(source)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func recordingRow(recording: Recording, range: AyahRange, segments: [RecordingSegment]) -> some View {
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

        let isPlaying = playbackVM.state.isActive
            && (playbackVM.currentAyah.map { range.contains($0) } ?? false)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rangeLabel).font(.body)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                if isPlaying {
                    playbackVM.stop()
                } else {
                    Task { await playbackVM.playRecording(range: range, recording: recording) }
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

        items.sort { lhs, rhs in
            switch (lhs.explicitOrder, rhs.explicitOrder) {
            case let (.some(lo), .some(ro)) where lo != ro: return lo < ro
            case (.some, nil): return true
            case (nil, .some): return false
            default: return tiebreakerIndex(lhs) < tiebreakerIndex(rhs)
            }
        }

        sources = items
        savedSourceOrder = items.map(\.id)
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
        savedSourceOrder = sources.map(\.id)
    }
}
