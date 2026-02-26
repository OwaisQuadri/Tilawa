import SwiftUI

/// The main Mushaf reading view with horizontal page swiping.
struct MushafView: View {
    @Environment(MushafViewModel.self) private var mushafVM
    @Environment(PlaybackViewModel.self) private var playbackVM

    @State private var showPlaybackSetup = false

    var body: some View {
        @Bindable var vm = mushafVM
        // Accessing currentAyah here establishes @Observable tracking so onChange fires reliably.
        let currentAyah = playbackVM.currentAyah

        NavigationStack {
            TabView(selection: $vm.currentPage) {
                // RTL layout: page 1 on right, swipe left to advance
                ForEach(1...604, id: \.self) { pageNumber in
                    MushafPageView(pageNumber: pageNumber)
                        .tag(pageNumber)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environment(\.layoutDirection, .rightToLeft)
            .ignoresSafeArea(.container, edges: .bottom)
            .onChange(of: mushafVM.currentPage, initial: true) { _, newPage in
                mushafVM.onPageChanged(to: newPage)
            }
            .task(id: mushafVM.currentPage) {
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
            .toolbarTitleDisplayMode(.inline)
            .ignoresSafeArea()
            .toolbar {
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
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
