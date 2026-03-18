import SwiftUI
import SwiftData

/// The main Mushaf reading view with vertical scrolling.
struct MushafView: View {
    @Environment(MushafViewModel.self) private var mushafVM
    @Environment(PlaybackViewModel.self) private var playbackVM

    @Environment(\.modelContext) private var modelContext
    @Query private var allBookmarks: [UserBookmark]
    @Query private var allPlaybackSettings: [PlaybackSettings]
    @State private var showPlaybackSetup = false

    /// Uses the @Observable-tracked downloadState (not filesystem checks) so SwiftUI
    /// re-evaluates when a PDF is downloaded or deleted.
    private var isPDFReady: Bool {
        if mushafVM.activeRiwayah == .hafs && mushafVM.mushafStyle == .indopak {
            return MushafPDFManager.shared.indopakDownloadState == .downloaded
        }
        return MushafPDFManager.shared.downloadState(for: mushafVM.activeRiwayah) == .downloaded
    }

    @Environment(\.colorScheme) private var colorScheme

    /// Background color that respects dark mode for PDF rendering.
    private var effectiveBackgroundColor: Color {
        if mushafVM.effectiveRenderingMode == .pdf && colorScheme == .dark {
            return .black
        }
        return mushafVM.theme.backgroundColor
    }

    /// Total pages: 604 for Hafs glyph, or the PDF's actual content page count.
    /// Returns 604 as fallback when the PDF isn't downloaded yet (the overlay covers the content).
    private var totalPageCount: Int {
        switch mushafVM.effectiveRenderingMode {
        case .hafsGlyph:
            return 604
        case .pdf:
            guard isPDFReady else { return 604 }
            if mushafVM.activeRiwayah == .hafs && mushafVM.mushafStyle == .indopak {
                return MushafPDFManager.shared.indopakContentPageCount
            }
            return MushafPDFManager.shared.contentPageCount(for: mushafVM.activeRiwayah)
        case .unicodeText:
            return 604
        }
    }

    var body: some View {
        @Bindable var vm = mushafVM
        // Accessing currentAyah here establishes @Observable tracking so onChange fires reliably.
        let currentAyah = playbackVM.currentAyah

        NavigationStack {
            TabView(selection: Binding(
                get: { mushafVM.currentPage },
                set: { mushafVM.onPageChanged(to: $0); Haptics.impact(.light) }
            )) {
                ForEach(1...totalPageCount, id: \.self) { pageNumber in
                    Group {
                        if mushafVM.effectiveRenderingMode == .pdf {
                            MushafPDFPageView(pageNumber: pageNumber)
                        } else {
                            MushafPageView(pageNumber: pageNumber)
                        }
                    }
                    .tag(pageNumber)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environment(\.layoutDirection, .rightToLeft)
            .background(effectiveBackgroundColor.ignoresSafeArea())
            .task(id: mushafVM.currentPage) {
                guard mushafVM.effectiveRenderingMode == .hafsGlyph else { return }
                let center = mushafVM.currentPage
                await withTaskGroup(of: Void.self) { group in
                    for p in max(1, center - 3)...min(604, center + 3) {
                        let page = p
                        group.addTask {
                            _ = try? await PageLayoutProvider.shared.layout(for: page)
                        }
                    }
                }
            }
            .onChange(of: currentAyah) { _, newAyah in
                // Highlighting is handled directly inside MushafPageView via playbackVM.currentAyah.
                // This handler only drives page navigation.
                if let ayah = newAyah {
                    mushafVM.scrollToAyah(ayah)
                }
            }
            .onChange(of: allPlaybackSettings.first?.selectedRiwayah) { _, newValue in
                mushafVM.activeRiwayah = Riwayah(rawValue: newValue ?? "") ?? .hafs
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbarBackground(effectiveBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(effectiveBackgroundColor, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Riwayah", selection: $vm.activeRiwayah) {
                            ForEach(Riwayah.availableForMushaf) { riwayah in
                                Text(riwayah.displayName).tag(riwayah)
                            }
                        }
                    } label: {
                        Image(systemName: "book")
                    }
                }
                ToolbarItem(placement: .title) {
                    MushafHeaderView()
                        .environment(\.layoutDirection, .leftToRight)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPlaybackSetup = true
                    } label: {
                        Image(systemName: "play.fill")
                            .symbolEffect(.pulse, isActive: playbackVM.state.isActive)
                    }
                }
            }
            .sheet(isPresented: $vm.showJumpSheet) {
                JumpToAyahSheet()
            }
            .sheet(isPresented: $showPlaybackSetup) {
                PlaybackSetupSheet()
            }
            .alert(vm.longPressedAyahTitle, isPresented: $vm.showAyahContextMenu) {
                Button("Play Ayah") { showPlaybackSetup = true }
                if let ref = vm.longPressedAyahRef,
                   let existing = allBookmarks.first(where: {
                       $0.surah == ref.surah && $0.ayah == ref.ayah
                   }) {
                    Button("Remove Bookmark", role: .destructive) {
                        Haptics.notification(.warning)
                        modelContext.delete(existing)
                    }
                } else {
                    Button("Bookmark Ayah") {
                        if let ref = vm.longPressedAyahRef {
                            let bookmark = UserBookmark(
                                surah: ref.surah,
                                ayah: ref.ayah,
                                page: vm.metadata.page(for: ref),
                                label: vm.longPressedAyahTitle
                            )
                            modelContext.insert(bookmark)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .overlay {
                if mushafVM.effectiveRenderingMode == .pdf && !isPDFReady {
                    PDFDownloadOverlay(
                        label: mushafVM.activeRiwayah == .hafs
                            ? "Indopak 15-line"
                            : mushafVM.activeRiwayah.displayName,
                        state: mushafVM.activeRiwayah == .hafs
                            ? MushafPDFManager.shared.indopakDownloadState
                            : MushafPDFManager.shared.downloadState(for: mushafVM.activeRiwayah),
                        onDownload: {
                            Task {
                                if mushafVM.activeRiwayah == .hafs {
                                    try? await MushafPDFManager.shared.downloadIndopak()
                                } else {
                                    try? await MushafPDFManager.shared.download(mushafVM.activeRiwayah)
                                }
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - PDF Download Overlay

/// Shown when a PDF mushaf is selected but not yet downloaded.
private struct PDFDownloadOverlay: View {
    let label: String
    let state: MushafPDFManager.DownloadState
    let onDownload: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(label)
                .font(.headline)

            switch state {
            case .notDownloaded, .failed:
                Text("This mushaf needs to be downloaded before viewing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: onDownload) {
                    Label("Download Mushaf", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)

                if case .failed = state {
                    Text("Download failed. Please try again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

            case .downloading(let progress):
                ProgressView(value: progress) {
                    Text("Downloading...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } currentValueLabel: {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 200)

            case .downloaded:
                EmptyView()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Page Divider

private struct PageDivider: View {
    let pageNumber: Int
    let theme: MushafTheme
    var body: some View {
        VStack(spacing: 4) {
            Text("\(pageNumber)")
                .font(.custom("TimesNewRoman", size: 20 , relativeTo: .title3))
                .foregroundStyle(theme.textColor)
            Divider()
                .padding(.top, 24)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(theme.backgroundColor)
    }
}
