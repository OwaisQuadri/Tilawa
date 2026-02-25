import Testing
import Foundation
import CoreText
@testable import Tilawa

struct MushafViewModelTests {

    private func makeVM() -> MushafViewModel {
        MushafViewModel()
    }

    @Test func initialState() {
        let vm = makeVM()
        #expect(vm.currentPage == 1)
        #expect(vm.highlightedAyah == nil)
        #expect(vm.highlightedWord == nil)
        #expect(vm.showJumpSheet == false)
    }

    @Test func jumpToSurahAyah() {
        let vm = makeVM()
        vm.jumpTo(surah: 2, ayah: 1)
        #expect(vm.currentPage == 2)
        #expect(vm.highlightedAyah == AyahRef(surah: 2, ayah: 1))
        #expect(vm.showJumpSheet == false)
    }

    @Test func jumpToPage() {
        let vm = makeVM()
        vm.jumpToPage(300)
        #expect(vm.currentPage == 300)
        #expect(vm.highlightedAyah == nil)
    }

    @Test func jumpToPageClamped() {
        let vm = makeVM()
        vm.jumpToPage(700)
        #expect(vm.currentPage == 604)

        vm.jumpToPage(0)
        #expect(vm.currentPage == 1)
    }

    @Test func handleWordTapSetsHighlight() {
        let vm = makeVM()
        let word = QULWord(location: "2:255:1", word: "ٱللَّهُ", qpcV2: nil, qpcV1: nil)
        let location = MushafPageUIView.WordLocation(
            pageNumber: 42,
            lineIndex: 3,
            wordIndex: 0,
            ayahRef: AyahRef(surah: 2, ayah: 255),
            word: word
        )
        vm.handleWordTap(location)
        #expect(vm.highlightedWord == location)
        #expect(vm.highlightedAyah == AyahRef(surah: 2, ayah: 255))
    }

    @Test func handleWordTapToggle() {
        let vm = makeVM()
        let word = QULWord(location: "2:255:1", word: "ٱللَّهُ", qpcV2: nil, qpcV1: nil)
        let location = MushafPageUIView.WordLocation(
            pageNumber: 42,
            lineIndex: 3,
            wordIndex: 0,
            ayahRef: AyahRef(surah: 2, ayah: 255),
            word: word
        )
        vm.handleWordTap(location)
        #expect(vm.highlightedWord != nil)

        // Tap same word again -> deselect
        vm.handleWordTap(location)
        #expect(vm.highlightedWord == nil)
        #expect(vm.highlightedAyah == nil)
    }

    @Test func highlightedWordOnPage() {
        let vm = makeVM()
        let word = QULWord(location: "1:1:1", word: "بِسْمِ", qpcV2: nil, qpcV1: nil)
        let location = MushafPageUIView.WordLocation(
            pageNumber: 1,
            lineIndex: 0,
            wordIndex: 0,
            ayahRef: AyahRef(surah: 1, ayah: 1),
            word: word
        )
        vm.handleWordTap(location)

        #expect(vm.highlightedWordOnPage(1) == location)
        #expect(vm.highlightedWordOnPage(2) == nil)
    }

    @Test func fontSizeAdjustment() {
        let vm = makeVM()
        let initial = vm.fontSize
        vm.increaseFontSize()
        #expect(vm.fontSize == initial + 2)
        vm.decreaseFontSize()
        #expect(vm.fontSize == initial)
    }

    @Test func currentSurahName() {
        let vm = makeVM()
        vm.jumpToPage(1)
        #expect(!vm.currentSurahName.isEmpty)
        #expect(!vm.currentSurahEnglishName.isEmpty)
    }
}
