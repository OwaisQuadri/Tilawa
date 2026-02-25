import SwiftUI

/// The main Mushaf reading view with horizontal page swiping.
struct MushafView: View {
    @Environment(MushafViewModel.self) private var mushafVM

    var body: some View {
        @Bindable var vm = mushafVM

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
            .toolbarTitleDisplayMode(.inline)
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .title) {
                    MushafHeaderView()
                        .environment(\.layoutDirection, .leftToRight)
                }

            }
            .sheet(isPresented: $vm.showJumpSheet) {
                JumpToAyahSheet()
            }
        }
    }
}
