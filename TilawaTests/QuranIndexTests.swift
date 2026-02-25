import Testing
@testable import Tilawa

struct QuranIndexTests {

    @Test func ayahRefEquality() {
        let a = AyahRef(surah: 2, ayah: 255)
        let b = AyahRef(surah: 2, ayah: 255)
        #expect(a == b)
    }

    @Test func ayahRefComparable() {
        let earlier = AyahRef(surah: 1, ayah: 7)
        let later = AyahRef(surah: 2, ayah: 1)
        #expect(earlier < later)

        let samesurah1 = AyahRef(surah: 3, ayah: 10)
        let samesurah2 = AyahRef(surah: 3, ayah: 20)
        #expect(samesurah1 < samesurah2)
    }

    @Test func ayahRangeContains() {
        let range = AyahRange(
            start: AyahRef(surah: 2, ayah: 1),
            end: AyahRef(surah: 2, ayah: 5)
        )
        #expect(range.contains(AyahRef(surah: 2, ayah: 3)))
        #expect(range.contains(AyahRef(surah: 2, ayah: 1)))
        #expect(range.contains(AyahRef(surah: 2, ayah: 5)))
        #expect(!range.contains(AyahRef(surah: 2, ayah: 6)))
        #expect(!range.contains(AyahRef(surah: 1, ayah: 7)))
    }

    @Test func ayahRangeCrossSurah() {
        let range = AyahRange(
            start: AyahRef(surah: 1, ayah: 5),
            end: AyahRef(surah: 2, ayah: 3)
        )
        #expect(range.contains(AyahRef(surah: 1, ayah: 7)))
        #expect(range.contains(AyahRef(surah: 2, ayah: 1)))
        #expect(!range.contains(AyahRef(surah: 2, ayah: 4)))
    }

    @Test func pageRef() {
        let p = PageRef(page: 604)
        #expect(p.page == 604)
    }
}
