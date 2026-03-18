import Testing
import Foundation
@testable import Tilawa

struct RiwayahPageLayoutBuilderTests {

    // MARK: - Page 1 (Al-Fatiha) in Warsh

    @Test func page1Warsh_hasFewerAyahsThanHafs() async throws {
        let content = try await RiwayahPageLayoutBuilder.shared.build(page: 1, riwayah: .warsh)
        let ayahRefs = content.ayahRefs

        // Warsh Al-Fatiha has 6 displayed ayahs (no separate Basmala ayah), vs Hafs 7.
        // Native numbering from offset map: 1,2,3,4,5,7 (6 is skipped due to alignment)
        #expect(ayahRefs.count == 6)
        #expect(ayahRefs.first == AyahRef(surah: 1, ayah: 1))
        #expect(ayahRefs.last == AyahRef(surah: 1, ayah: 7))
    }

    @Test func page1Warsh_hasSurahHeader() async throws {
        let content = try await RiwayahPageLayoutBuilder.shared.build(page: 1, riwayah: .warsh)
        let hasHeader = content.elements.contains {
            if case .surahHeader = $0 { return true }
            return false
        }
        #expect(hasHeader)
    }

    @Test func page1Hafs_hasFatihaBasmala() async throws {
        // Page 1 Hafs has 7 ayahs including the Basmala
        let content = try await RiwayahPageLayoutBuilder.shared.build(page: 1, riwayah: .hafs)
        let ayahRefs = content.ayahRefs
        #expect(ayahRefs.count == 7)
        #expect(ayahRefs.first == AyahRef(surah: 1, ayah: 1))
    }

    // MARK: - Page 2 (Start of Al-Baqarah) in Warsh

    @Test func page2Warsh_mergedAyahs() async throws {
        // In Warsh, Hafs 2:1 (Alif-Lam-Meem) and 2:2 are merged into Warsh 2:1
        let content = try await RiwayahPageLayoutBuilder.shared.build(page: 2, riwayah: .warsh)
        let ayahRefs = content.ayahRefs

        // Should not have duplicate entries for the same native ayah
        let uniqueRefs = Set(ayahRefs)
        #expect(ayahRefs.count == uniqueRefs.count, "No duplicate ayah refs")
    }

    @Test func page2Warsh_hasSurahHeaderAndBasmala() async throws {
        let content = try await RiwayahPageLayoutBuilder.shared.build(page: 2, riwayah: .warsh)
        let hasHeader = content.elements.contains {
            if case .surahHeader = $0 { return true }
            return false
        }
        let hasBasmala = content.elements.contains {
            if case .basmala = $0 { return true }
            return false
        }
        #expect(hasHeader)
        #expect(hasBasmala)
    }

    // MARK: - Riwayah with identity mapping (Shu'bah)

    @Test func page1Shuabah_sameAsHafs() async throws {
        // Shu'bah has identity mapping (same ayah numbering as Hafs)
        let hafsContent = try await RiwayahPageLayoutBuilder.shared.build(page: 1, riwayah: .hafs)
        let shuabahContent = try await RiwayahPageLayoutBuilder.shared.build(page: 1, riwayah: .shuabah)

        #expect(hafsContent.ayahRefs.count == shuabahContent.ayahRefs.count)
    }

    // MARK: - No self-duplication

    @Test func page1Warsh_noSelfDuplicatedAyahText() async throws {
        let content = try await RiwayahPageLayoutBuilder.shared.build(page: 1, riwayah: .warsh)
        for element in content.elements {
            guard case .ayahText(_, _, let text) = element else { continue }
            // Each ayah's text should appear exactly once, not concatenated with itself.
            // Split into words and check that the first half doesn't equal the second half.
            let words = text.split(separator: " ")
            guard words.count >= 4 else { continue }
            let half = words.count / 2
            let firstHalf = words[0..<half].joined(separator: " ")
            let secondHalf = words[half..<(half * 2)].joined(separator: " ")
            #expect(firstHalf != secondHalf, "Ayah text should not be self-duplicated: \(text.prefix(60))...")
        }
    }

    // MARK: - Text content correctness

    @Test func warshTextDiffersFromHafs() async throws {
        // Al-Fatiha 1:4 differs: Hafs "مَٰلِكِ" vs Warsh "مَلِكِ"
        let hafsContent = try await RiwayahPageLayoutBuilder.shared.build(page: 1, riwayah: .hafs)
        let warshContent = try await RiwayahPageLayoutBuilder.shared.build(page: 1, riwayah: .warsh)

        // Get ayah text for what would be 1:4 in Hafs (1:3 in Warsh = Maaliki/Maliki yawm ad-deen)
        let hafsAyah4 = hafsContent.elements.compactMap { element -> String? in
            if case .ayahText(1, 4, let text) = element { return text }
            return nil
        }.first

        let warshAyah3 = warshContent.elements.compactMap { element -> String? in
            if case .ayahText(1, 3, let text) = element { return text }
            return nil
        }.first

        #expect(hafsAyah4 != nil)
        #expect(warshAyah3 != nil)
        // The text content should differ (different readings of this ayah)
        #expect(hafsAyah4 != warshAyah3)
    }
}
