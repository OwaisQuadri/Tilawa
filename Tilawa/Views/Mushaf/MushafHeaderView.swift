import SwiftUI

/// Navigation bar title for the Mushaf reader.
/// Shows surah info, page number, and Juz/Hizb/Thumun position.
struct MushafHeaderView: View {
    @Environment(MushafViewModel.self) private var mushafVM

    private var surah: QuranMetadataService.SurahInfo? {
        mushafVM.metadata.surahOnPage(mushafVM.currentPage)
    }

    private var juzInfo: JuzInfo {
        JuzService.shared.juzInfo(forPage: mushafVM.currentPage)
    }

    private var ayahRangeText: String? {
        guard let range = mushafVM.currentPageAyahRange else { return nil }
        if range.first.surah == range.last.surah {
            return "\(range.first.ayah)–\(range.last.ayah)"
        } else {
            return "\(range.first.surah):\(range.first.ayah)–\(range.last.surah):\(range.last.ayah)"
        }
    }

    private var thumunLabel: String {
        switch juzInfo.thumunInHizb {
        case 2: return "¼"
        case 3: return "½"
        case 4: return "¾"
        default: return ""
        }
    }

    var body: some View {
        VStack(spacing: 1) {
            // Row 1: surah number · Arabic name · English name · ayah range
            HStack(spacing: 4) {
                if let surah {
                    Text("\(surah.number).")
                    Text(surah.englishName)
                    Text("·")
                    Text(surah.name)
                        .environment(\.layoutDirection, .rightToLeft)
                    if let range = ayahRangeText {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(range)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.subheadline.weight(.semibold))

            // Row 2: page · Juz · Hizb (· thumun fraction if not start of hizb)
            // Section is bolded when the current page opens on a thumun boundary
            HStack(spacing: 5) {
                Text("Page \(mushafVM.currentPage)")

                Text("·")

                HStack(spacing: 4) {
                    Text("Juz \(juzInfo.juz)")
                    Text("·")
                    Text("Hizb \(juzInfo.hizb)")
                    if !thumunLabel.isEmpty {
                        Text(thumunLabel)
                    }
                }
                .fontWeight(juzInfo.isOnThumunBoundary ? .bold : .regular)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
