import SwiftUI
import SwiftData

@main
struct TilawaApp: App {
    @State private var mushafViewModel = MushafViewModel()
    @State private var playbackViewModel = PlaybackViewModel(
        engine: PlaybackEngine(
            resolver: ReciterResolver(
                libraryService: RecordingLibraryServiceImpl(container: TilawaApp.sharedModelContainer)
            )
        )
    )

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PlaybackSettings.self,
            ReciterPriorityEntry.self,
            ReciterSegmentOverride.self,
            SegmentReciterEntry.self,
            Reciter.self,
            ReciterCDNSource.self,
            Recording.self,
            RecordingSegment.self,
            AyahMarker.self,
            UserBookmark.self,
            ListeningSession.self,
        ])
        // CloudKit sync is deferred until the iCloud entitlement is added.
        // To enable: replace ModelConfiguration with:
        //   ModelConfiguration("TilawaCloud", schema: schema, cloudKitDatabase: .automatic)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(mushafViewModel)
                .environment(playbackViewModel)
                .modelContainer(TilawaApp.sharedModelContainer)
                .task { await seedDefaultReciterIfNeeded() }
                .task { DownloadManager.shared.requestNotificationPermission() }
        }
    }

    // MARK: - First-Launch Seeding

    /// Seeds Minshawi as the default reciter if no reciters exist in the database.
    /// Also patches any stale base URLs that were saved before the CDN folder name was corrected.
    @MainActor
    private func seedDefaultReciterIfNeeded() async {
        let context = TilawaApp.sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Reciter>()
        let existing = (try? context.fetch(descriptor)) ?? []

        // Patch: fix the folder name typo (Minshawi_ → Minshawy_) saved by older builds
        var patched = false
        for reciter in existing {
            for source in reciter.cdnSources ?? [] {
                if source.baseURL?.contains("Minshawi_Murattal_128kbps") == true {
                    source.baseURL = source.baseURL?
                        .replacingOccurrences(of: "Minshawi_Murattal_128kbps", with: "Minshawy_Murattal_128kbps")
                    patched = true
                    print("🔧 Patched CDN source URL: \(reciter.safeName) → \(source.baseURL ?? "")")
                }
            }
        }
        if patched { try? context.save() }

        guard existing.isEmpty else { return }

        guard let jsonURL = Bundle.main.url(
            forResource: "minshawi_murattal",
            withExtension: "json"
        ) else {
            assertionFailure("minshawi_murattal.json not found in bundle")
            return
        }

        do {
            let importer = ReciterManifestImporter()
            let reciter = try importer.importManifest(from: jsonURL, context: context)

            // Add Minshawi as the sole entry in default PlaybackSettings
            let settings = PlaybackSettings.makeDefault()
            let priorityEntry = ReciterPriorityEntry(order: 0, reciterId: reciter.id!)
            settings.reciterPriority = [priorityEntry]
            context.insert(settings)

            try context.save()
            print("✅ Seeded reciter: \(reciter.safeName) (\(reciter.riwayahSummaryLabel)) id=\(reciter.id!)")
        } catch {
            assertionFailure("Failed to seed default reciter: \(error)")
        }
    }
}
