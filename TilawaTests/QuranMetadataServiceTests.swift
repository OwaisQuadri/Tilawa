import Testing
@testable import Tilawa

struct QuranMetadataServiceTests {

    private func makeService() -> QuranMetadataService {
        // Use the real bundled metadata
        QuranMetadataService.shared
    }

    @Test func surahCount() {
        let svc = makeService()
        #expect(svc.surahs.count == 114)
    }

    @Test func totalAyahCount() {
        let svc = makeService()
        #expect(svc.totalAyahCount == 6236)
    }

    @Test func alFatihah() {
        let svc = makeService()
        let fatihah = svc.surah(1)
        #expect(fatihah != nil)
        #expect(fatihah?.ayahCount == 7)
        #expect(fatihah?.startPage == 1)
        #expect(fatihah?.englishName == "Al-Fatihah")
    }

    @Test func alBaqarahStartsPage2() {
        let svc = makeService()
        #expect(svc.surah(2)?.startPage == 2)
    }

    @Test func anNasOnPage604() {
        let svc = makeService()
        #expect(svc.surah(114)?.startPage == 604)
    }

    @Test func surahOnPage() {
        let svc = makeService()
        let s = svc.surahOnPage(1)
        #expect(s?.number == 1)

        let s2 = svc.surahOnPage(50)
        #expect(s2?.number == 3) // Ali Imran starts on page 50
    }

    @Test func pageForAyah() {
        let svc = makeService()
        // First ayah of first surah should be page 1
        let p = svc.page(for: AyahRef(surah: 1, ayah: 1))
        #expect(p == 1)
    }

    @Test func ayahAfter() {
        let svc = makeService()
        let next = svc.ayah(after: AyahRef(surah: 1, ayah: 7))
        #expect(next == AyahRef(surah: 2, ayah: 1))
    }

    @Test func ayahAfterLastAyahInQuran() {
        let svc = makeService()
        let last = svc.ayah(after: AyahRef(surah: 114, ayah: 6))
        #expect(last == nil)
    }

    @Test func ayahBefore() {
        let svc = makeService()
        let prev = svc.ayah(before: AyahRef(surah: 2, ayah: 1))
        #expect(prev == AyahRef(surah: 1, ayah: 7))
    }

    @Test func ayahBeforeFirstAyahInQuran() {
        let svc = makeService()
        let first = svc.ayah(before: AyahRef(surah: 1, ayah: 1))
        #expect(first == nil)
    }

    @Test func firstAyahOfSurah() {
        let svc = makeService()
        #expect(svc.firstAyah(ofSurah: 36) == AyahRef(surah: 36, ayah: 1))
    }

    @Test func invalidSurah() {
        let svc = makeService()
        #expect(svc.surah(0) == nil)
        #expect(svc.surah(115) == nil)
    }
}
