# Tilawa — Data Models

**Version:** 1.1

All `@Model` classes follow three invariants:
1. `id: UUID?` — required for CloudKit sync via SwiftData
2. All stored properties are `Optional` — required for CloudKit record compatibility
3. Every `@Model` has a nil-initializer (`init()`) that sets all attributes to `nil` — CloudKit may
   reconstruct model instances with no data and populate fields asynchronously
4. Convenience computed properties (non-stored, non-optional) are used in all business logic and UI

---

## 1. SwiftData @Model Classes

### PlaybackSettings.swift

```swift
import SwiftData
import Foundation

@Model
final class PlaybackSettings {
    var id: UUID?

    // --- Playback Range ---
    var startSurah: Int?           // 1–114
    var startAyah: Int?            // 1–N
    var endSurah: Int?
    var endAyah: Int?
    var usePageRange: Bool?        // if true, use startPage/endPage instead of ayah range
    var startPage: Int?            // 1–604
    var endPage: Int?

    // --- Connection Ayah ---
    var connectionAyahBefore: Int? // 0 = disabled, 1 = include 1 ayah before start
    var connectionAyahAfter: Int?  // 0 = disabled, 1 = include 1 ayah after end

    // --- Playback Control ---
    var playbackSpeed: Double?     // 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0
    var gapBetweenAyaatMs: Int?    // 0–3000 ms

    // --- Repeat ---
    var ayahRepeatCount: Int?      // 1–100, or -1 = infinite
    var rangeRepeatCount: Int?     // 1–100, or -1 = infinite

    // --- After-Range-Repeat Behavior ---
    // "stop" | "continueAyaat" | "continuePages"
    var afterRepeatAction: String?
    var afterRepeatContinueAyaatCount: Int?
    var afterRepeatContinuePagesCount: Int?

    // --- Riwayah (stored as raw string for CloudKit compat) ---
    var selectedRiwayah: String?   // Riwayah.rawValue

    // --- Reciter Priority (ordered list) ---
    @Relationship(deleteRule: .cascade)
    var reciterPriority: [ReciterPriorityEntry]?

    // --- Display ---
    var showWordByWordHighlight: Bool?
    var showRepetitionCounter: Bool?
    var showReciterName: Bool?

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.startSurah = nil; self.startAyah = nil
        self.endSurah = nil; self.endAyah = nil
        self.usePageRange = nil; self.startPage = nil; self.endPage = nil
        self.connectionAyahBefore = nil; self.connectionAyahAfter = nil
        self.playbackSpeed = nil; self.gapBetweenAyaatMs = nil
        self.ayahRepeatCount = nil; self.rangeRepeatCount = nil
        self.afterRepeatAction = nil
        self.afterRepeatContinueAyaatCount = nil; self.afterRepeatContinuePagesCount = nil
        self.selectedRiwayah = nil
        self.reciterPriority = nil
        self.showWordByWordHighlight = nil
        self.showRepetitionCounter = nil; self.showReciterName = nil
    }

    // MARK: - Convenience initializer with defaults
    static func makeDefault() -> PlaybackSettings {
        let s = PlaybackSettings()
        s.id = UUID()
        s.playbackSpeed = 1.0
        s.gapBetweenAyaatMs = 0
        s.ayahRepeatCount = 1
        s.rangeRepeatCount = 1
        s.afterRepeatAction = AfterRepeatAction.stop.rawValue
        s.connectionAyahBefore = 0
        s.connectionAyahAfter = 0
        s.selectedRiwayah = Riwayah.hafs.rawValue
        s.usePageRange = false
        s.showWordByWordHighlight = true
        s.showRepetitionCounter = true
        s.showReciterName = true
        return s
    }

    // MARK: - Safe computed properties
    var safeSpeed: Double { playbackSpeed ?? 1.0 }
    var safeAyahRepeat: Int { ayahRepeatCount ?? 1 }
    var safeRangeRepeat: Int { rangeRepeatCount ?? 1 }
    var safeGapMs: Int { gapBetweenAyaatMs ?? 0 }
    var safeRiwayah: Riwayah { Riwayah(rawValue: selectedRiwayah ?? "") ?? .hafs }
    var safeAfterRepeatAction: AfterRepeatAction {
        AfterRepeatAction(rawValue: afterRepeatAction ?? "") ?? .stop
    }
    var sortedReciterPriority: [ReciterPriorityEntry] {
        (reciterPriority ?? [])
            .filter { $0.isEnabled ?? true }
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }
}
```

---

### ReciterPriorityEntry.swift

```swift
// One entry in the user's ordered reciter priority list.
// Riwayah matching is always strict at the session level — see CHALLENGES.md #9.
// A single Reciter entry covers both its personal recordings AND its CDN files;
// the resolver checks personal recordings first, then CDN, for each entry in order.
@Model
final class ReciterPriorityEntry {
    var id: UUID?
    var order: Int?        // 0 = highest priority
    var reciterId: UUID?   // references Reciter.id
    var isEnabled: Bool?

    @Relationship(inverse: \PlaybackSettings.reciterPriority)
    var settings: PlaybackSettings?

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.order = nil
        self.reciterId = nil
        self.isEnabled = nil
        self.settings = nil
    }

    // MARK: - Convenience initializer
    convenience init(order: Int, reciterId: UUID) {
        self.init()
        self.id = UUID()
        self.order = order
        self.reciterId = reciterId
        self.isEnabled = true
    }
}
```

---

### Reciter.swift

```swift
// Represents a named reciter (sheikh). A Reciter can have BOTH:
//   - CDN-backed audio files (remoteBaseURL + fileNamingPattern)
//   - Personal recordings uploaded by the user (linked via Recording.reciter)
// Example: Yasser al-Dosari may have a CDN entry for his studio recitations
// AND personal Recording objects for Friday prayers the user attended.
// The resolver checks personal recordings first, then CDN, for each reciter.
@Model
final class Reciter {
    var id: UUID?
    var name: String?                // "Yasser al-Dosari"
    var shortName: String?           // "Dosari"
    var riwayah: String?             // Riwayah.rawValue — the reciter's riwayah
    var remoteBaseURL: String?       // "https://cdn.example.com/reciters/dosari/"
    var localCacheDirectory: String? // relative path in app Caches dir
    var audioFileFormat: String?     // "mp3" | "opus" | "m4a"
    // Naming pattern tokens: {surah3} = zero-padded 3-digit, {ayah3} = zero-padded 3-digit
    // Example: "{surah3}{ayah3}.mp3" → "002005.mp3"
    var fileNamingPattern: String?
    var isDownloaded: Bool?          // true when all requested surahs are cached locally
    var downloadedSurahsJSON: String? // JSON [Int] of fully-downloaded surah numbers
    var coverImageURL: String?
    var sortOrder: Int?

    @Relationship(deleteRule: .cascade)
    var recordings: [Recording]?    // personal recordings linked to this reciter

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.name = nil; self.shortName = nil
        self.riwayah = nil
        self.remoteBaseURL = nil; self.localCacheDirectory = nil
        self.audioFileFormat = nil; self.fileNamingPattern = nil
        self.isDownloaded = nil; self.downloadedSurahsJSON = nil
        self.coverImageURL = nil; self.sortOrder = nil
        self.recordings = nil
    }

    // MARK: - Convenience initializer
    convenience init(name: String, riwayah: Riwayah) {
        self.init()
        self.id = UUID()
        self.name = name
        self.riwayah = riwayah.rawValue
        self.isDownloaded = false
        self.audioFileFormat = "mp3"
        self.fileNamingPattern = "{surah3}{ayah3}.mp3"
    }

    var safeName: String { name ?? "Unknown Reciter" }
    var safeRiwayah: Riwayah { Riwayah(rawValue: riwayah ?? "") ?? .hafs }
    var hasCDN: Bool { remoteBaseURL != nil }
    var hasPersonalRecordings: Bool { !(recordings ?? []).isEmpty }
}
```

---

### Recording.swift

```swift
@Model
final class Recording {
    var id: UUID?
    var title: String?
    var sourceFileName: String?       // original filename when imported
    // Relative path within iCloud ubiquity container.
    // Full URL: ubiquityContainerURL.appendingPathComponent(storagePath)
    var storagePath: String?
    var durationSeconds: Double?
    var fileFormat: String?           // "m4a" | "mp3" | "wav" | "caf"
    var fileSizeBytes: Int?
    var importedAt: Date?
    var recordedAt: Date?             // from file metadata if available
    // "unannotated" | "partial" | "complete"
    var annotationStatus: String?
    var notes: String?

    // Denormalized coverage cache (updated whenever segments change)
    var coversSurahStart: Int?
    var coversSurahEnd: Int?

    // The reciter this recording belongs to (may be nil until user assigns)
    var reciter: Reciter?

    @Relationship(deleteRule: .cascade)
    var segments: [RecordingSegment]?

    @Relationship(deleteRule: .cascade)
    var markers: [AyahMarker]?        // ephemeral; cleared after annotations are saved

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.title = nil; self.sourceFileName = nil; self.storagePath = nil
        self.durationSeconds = nil; self.fileFormat = nil; self.fileSizeBytes = nil
        self.importedAt = nil; self.recordedAt = nil
        self.annotationStatus = nil; self.notes = nil
        self.coversSurahStart = nil; self.coversSurahEnd = nil
        self.reciter = nil; self.segments = nil; self.markers = nil
    }

    // MARK: - Convenience initializer
    convenience init(title: String, storagePath: String) {
        self.init()
        self.id = UUID()
        self.title = title
        self.storagePath = storagePath
        self.importedAt = Date()
        self.annotationStatus = AnnotationStatus.unannotated.rawValue
    }

    var safeTitle: String { title ?? "Untitled Recording" }
    var safeDuration: Double { durationSeconds ?? 0 }
    var annotationStatusEnum: AnnotationStatus {
        AnnotationStatus(rawValue: annotationStatus ?? "") ?? .unannotated
    }
    var sortedSegments: [RecordingSegment] {
        (segments ?? []).sorted { ($0.startOffsetSeconds ?? 0) < ($1.startOffsetSeconds ?? 0) }
    }
}
```

---

### RecordingSegment.swift

```swift
@Model
final class RecordingSegment {
    var id: UUID?
    var recording: Recording?

    // --- Audio position within the recording file ---
    var startOffsetSeconds: Double?
    var endOffsetSeconds: Double?

    // --- Primary Quran reference ---
    var surahNumber: Int?    // 1–114
    var ayahNumber: Int?     // 1–N

    // --- Cross-surah support ---
    // For single-ayah segments: endSurahNumber == surahNumber, endAyahNumber == ayahNumber
    var endSurahNumber: Int?
    var endAyahNumber: Int?
    // true when this segment spans a surah boundary with no audible gap
    // (canonical example: Anfal 8:75 recited directly into Tawbah 9:1)
    var isCrosssurahSegment: Bool?
    // Time within the segment where the surah boundary occurs.
    // Used to split into two virtual AyahAudioItems during resolution.
    var crossSurahJoinOffsetSeconds: Double?

    // --- Quality ---
    var isManuallyAnnotated: Bool?   // true = human-verified placement
    var confidenceScore: Double?     // 0.0–1.0 from silence detection

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.recording = nil
        self.startOffsetSeconds = nil; self.endOffsetSeconds = nil
        self.surahNumber = nil; self.ayahNumber = nil
        self.endSurahNumber = nil; self.endAyahNumber = nil
        self.isCrosssurahSegment = nil; self.crossSurahJoinOffsetSeconds = nil
        self.isManuallyAnnotated = nil; self.confidenceScore = nil
    }

    // MARK: - Convenience initializer
    convenience init(recording: Recording,
                     startOffset: Double, endOffset: Double,
                     surah: Int, ayah: Int) {
        self.init()
        self.id = UUID()
        self.recording = recording
        self.startOffsetSeconds = startOffset
        self.endOffsetSeconds = endOffset
        self.surahNumber = surah; self.ayahNumber = ayah
        self.endSurahNumber = surah; self.endAyahNumber = ayah
        self.isCrosssurahSegment = false
        self.isManuallyAnnotated = false
        self.confidenceScore = 0.0
    }

    var safeDuration: Double { (endOffsetSeconds ?? 0) - (startOffsetSeconds ?? 0) }
    var primaryAyahRef: AyahRef { AyahRef(surah: surahNumber ?? 1, ayah: ayahNumber ?? 1) }
    var endAyahRef: AyahRef {
        AyahRef(surah: endSurahNumber ?? surahNumber ?? 1,
                ayah: endAyahNumber ?? ayahNumber ?? 1)
    }
}
```

---

### AyahMarker.swift

```swift
// Temporary annotation marker placed on the waveform during editing.
// Converted to RecordingSegments when the user saves.
// Persisted so the editor can be closed and reopened without losing unsaved work.
@Model
final class AyahMarker {
    var id: UUID?
    var recording: Recording?
    var positionSeconds: Double?
    var markerIndex: Int?           // display order (0 = first)
    var isConfirmed: Bool?          // true once ayah is assigned
    var assignedSurah: Int?
    var assignedAyah: Int?

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.recording = nil
        self.positionSeconds = nil; self.markerIndex = nil
        self.isConfirmed = nil
        self.assignedSurah = nil; self.assignedAyah = nil
    }

    // MARK: - Convenience initializer
    convenience init(recording: Recording, position: Double, index: Int) {
        self.init()
        self.id = UUID()
        self.recording = recording
        self.positionSeconds = position
        self.markerIndex = index
        self.isConfirmed = false
    }

    var assignedRef: AyahRef? {
        guard let s = assignedSurah, let a = assignedAyah else { return nil }
        return AyahRef(surah: s, ayah: a)
    }
}
```

---

### UserBookmark.swift

```swift
@Model
final class UserBookmark {
    var id: UUID?
    var surahNumber: Int?
    var ayahNumber: Int?
    var pageNumber: Int?
    var label: String?
    var createdAt: Date?
    var colorHex: String?

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.surahNumber = nil; self.ayahNumber = nil; self.pageNumber = nil
        self.label = nil; self.createdAt = nil; self.colorHex = nil
    }

    // MARK: - Convenience initializer
    convenience init(surah: Int, ayah: Int, page: Int) {
        self.init()
        self.id = UUID()
        self.surahNumber = surah
        self.ayahNumber = ayah
        self.pageNumber = page
        self.createdAt = Date()
    }
}
```

---

### ListeningSession.swift

```swift
// Tracks the user's reading/listening position for resume.
// Only one instance exists; fetch with a @Query and take the first result.
@Model
final class ListeningSession {
    var id: UUID?
    var lastSurah: Int?
    var lastAyah: Int?
    var lastPage: Int?
    var lastUpdatedAt: Date?
    var totalListeningSeconds: Double?

    // MARK: - Nil initializer (required for CloudKit)
    init() {
        self.id = nil
        self.lastSurah = nil; self.lastAyah = nil; self.lastPage = nil
        self.lastUpdatedAt = nil; self.totalListeningSeconds = nil
    }

    // MARK: - Convenience initializer
    static func makeNew() -> ListeningSession {
        let s = ListeningSession()
        s.id = UUID()
        s.lastUpdatedAt = Date()
        s.totalListeningSeconds = 0.0
        return s
    }
}
```

---

## 2. Value Types (Non-persisted)

```swift
// QuranIndex.swift

struct AyahRef: Hashable, Codable, Sendable {
    let surah: Int  // 1–114
    let ayah: Int   // 1–N (Hafs standard counts)

    var isValid: Bool { surah >= 1 && surah <= 114 && ayah >= 1 }

    static func basmallah(before surah: Int) -> AyahRef {
        AyahRef(surah: surah, ayah: 0)  // ayah 0 = Bismillah (not a numbered ayah)
    }
}

struct PageRef: Hashable, Codable, Sendable {
    let page: Int  // 1–604
}

struct AyahRange: Hashable, Sendable {
    let start: AyahRef
    let end: AyahRef
}

// Immutable snapshot of PlaybackSettings captured at play() time.
// Settings changes during a session do NOT affect the running session.
struct PlaybackSettingsSnapshot: Sendable {
    let range: AyahRange
    let connectionAyahBefore: Int
    let connectionAyahAfter: Int
    let speed: Double
    let ayahRepeatCount: Int        // -1 = infinite
    let rangeRepeatCount: Int       // -1 = infinite
    let afterRepeatAction: AfterRepeatAction
    let gapBetweenAyaatMs: Int
    let reciterPriority: [ReciterSnapshot]
    let riwayah: Riwayah
}

// Snapshot of one priority entry + its resolved Reciter object
struct ReciterSnapshot: Sendable {
    let reciterId: UUID
    let reciter: Reciter
}

// The resolved, playable unit for one ayah. Built by ReciterResolver.
struct AyahAudioItem: Identifiable, Sendable {
    let id: UUID
    let ayahRef: AyahRef
    let audioURL: URL
    let startOffset: TimeInterval   // 0 for full CDN files; >0 for UGC segments
    let endOffset: TimeInterval
    let reciterName: String
    let reciterId: UUID
    let isPersonalRecording: Bool   // true = sourced from a user Recording, not CDN
    let wordTimings: [WordTiming]?
}

struct WordTiming: Codable, Sendable {
    let wordIndex: Int              // 0-based index within the ayah
    let startSeconds: Double        // position in the original (1×) audio file
    let endSeconds: Double
}
```

---

## 3. Supporting Enums

### Riwayah.swift

```swift
// The 14 canonical riwayat from the 7 mutawatir qira'at (plus the 3 mashhur completing the 10).
// Stored as String rawValue in @Model fields for CloudKit compatibility.
//
// Future expansion: Turuk (طرق) — transmission sub-chains within a riwayah
// (e.g., Warsh via Tariq al-Azraq vs. Tariq al-Asbahani) — will be modeled as a
// separate associated type or sibling enum when needed.
enum Riwayah: String, CaseIterable, Codable {

    // ── Asim (عاصم) ────────────────────────────────────────────
    case hafs    = "hafs"     // رواية حفص — most widely used globally
    case shuabah = "shuabah"  // رواية شعبة

    // ── Nafi (نافع) ────────────────────────────────────────────
    case warsh  = "warsh"    // رواية ورش — dominant in North/West Africa
    case qaloon = "qaloon"   // رواية قالون — dominant in Libya, Tunisia, parts of Gulf

    // ── Ibn Kathir (ابن كثير) ───────────────────────────────────
    case bazzi  = "bazzi"    // رواية البزي
    case qunbul = "qunbul"   // رواية قنبل

    // ── Abu Amr al-Basri (أبو عمرو البصري) ─────────────────────
    case dooriAbuAmr = "doori_abu_amr"  // رواية الدوري عن أبي عمرو
    case soosi       = "soosi"          // رواية السوسي

    // ── Ibn Amir al-Shami (ابن عامر الشامي) ─────────────────────
    case hisham    = "hisham"     // رواية هشام
    case ibnDhakwan = "ibn_dhakwan" // رواية ابن ذكوان

    // ── Hamza (حمزة) ───────────────────────────────────────────
    case khalafAnHamza = "khalaf_an_hamza"  // رواية خلف عن حمزة
    case khallad       = "khallad"          // رواية خلاد

    // ── Al-Kisai (الكسائي) ─────────────────────────────────────
    case abulHarith   = "abul_harith"    // رواية أبي الحارث
    case dooriAlKisai = "doori_al_kisai" // رواية الدوري عن الكسائي

    // ── Abu Jafar (أبو جعفر) — from the 10 qira'at ─────────────
    case ibnWardan  = "ibn_wardan"  // رواية ابن وردان
    case ibnJammaz  = "ibn_jammaz"  // رواية ابن جماز

    // ── Yaqub al-Hadrami (يعقوب الحضرمي) ──────────────────────
    case ruways = "ruways"  // رواية رويس
    case rawh   = "rawh"    // رواية روح

    // ── Khalaf al-Ashir (خلف العاشر) ───────────────────────────
    case ishaq = "ishaq"  // رواية إسحاق
    case idris = "idris"  // رواية إدريس

    // MARK: - Metadata
    var displayName: String {
        switch self {
        case .hafs:           return "Hafs an Asim"
        case .shuabah:        return "Shu'bah an Asim"
        case .warsh:          return "Warsh an Nafi"
        case .qaloon:         return "Qaloon an Nafi"
        case .bazzi:          return "Al-Bazzi an Ibn Kathir"
        case .qunbul:         return "Qunbul an Ibn Kathir"
        case .dooriAbuAmr:    return "Ad-Doori an Abi Amr"
        case .soosi:          return "As-Soosi an Abi Amr"
        case .hisham:         return "Hisham an Ibn Amir"
        case .ibnDhakwan:     return "Ibn Dhakwan an Ibn Amir"
        case .khalafAnHamza:  return "Khalaf an Hamza"
        case .khallad:        return "Khallad an Hamza"
        case .abulHarith:     return "Abu'l-Harith an al-Kisai"
        case .dooriAlKisai:   return "Ad-Doori an al-Kisai"
        case .ibnWardan:      return "Ibn Wardan an Abi Jafar"
        case .ibnJammaz:      return "Ibn Jammaz an Abi Jafar"
        case .ruways:         return "Ruways an Yaqub"
        case .rawh:           return "Rawh an Yaqub"
        case .ishaq:          return "Ishaq an Khalaf al-Ashir"
        case .idris:          return "Idris an Khalaf al-Ashir"
        }
    }

    var qira_ah: String {
        switch self {
        case .hafs, .shuabah:             return "Asim"
        case .warsh, .qaloon:             return "Nafi"
        case .bazzi, .qunbul:             return "Ibn Kathir"
        case .dooriAbuAmr, .soosi:        return "Abu Amr"
        case .hisham, .ibnDhakwan:        return "Ibn Amir"
        case .khalafAnHamza, .khallad:    return "Hamza"
        case .abulHarith, .dooriAlKisai:  return "Al-Kisai"
        case .ibnWardan, .ibnJammaz:      return "Abu Jafar"
        case .ruways, .rawh:              return "Yaqub"
        case .ishaq, .idris:              return "Khalaf al-Ashir"
        }
    }
}
```

### Other Enums

```swift
enum AfterRepeatAction: String, CaseIterable {
    case stop           = "stop"
    case continueAyaat  = "continueAyaat"
    case continuePages  = "continuePages"
}

enum AnnotationStatus: String {
    case unannotated = "unannotated"
    case partial     = "partial"
    case complete    = "complete"
}
```

---

## 4. ModelContainer Configuration

```swift
// TilawaApp.swift
var sharedModelContainer: ModelContainer = {
    let schema = Schema([
        PlaybackSettings.self,
        ReciterPriorityEntry.self,
        Reciter.self,
        Recording.self,
        RecordingSegment.self,
        AyahMarker.self,
        UserBookmark.self,
        ListeningSession.self,
    ])

    let config = ModelConfiguration(
        "TilawaCloud",
        schema: schema,
        cloudKitDatabase: .automatic
    )

    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        fatalError("Could not create ModelContainer: \(error)")
    }
}()
```

---

## 5. Schema Migration Strategy

```swift
enum TilawaSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [PlaybackSettings.self, ReciterPriorityEntry.self, Reciter.self,
         Recording.self, RecordingSegment.self, AyahMarker.self,
         UserBookmark.self, ListeningSession.self]
    }
}

struct TilawaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [TilawaSchemaV1.self]
    static var stages: [MigrationStage] = []
}
```

New fields always added as optionals; safe computed properties handle `nil` defaults.
Renamed/removed fields use lightweight `willMigrate`/`didMigrate` closures only when required.
