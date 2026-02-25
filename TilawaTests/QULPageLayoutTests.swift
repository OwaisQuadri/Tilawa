import Testing
import Foundation
@testable import Tilawa

struct QULPageLayoutTests {

    @Test func decodePageOneJSON() throws {
        let json = """
        {
          "page": 1,
          "lines": [
            {
              "line": 1,
              "type": "surah-header",
              "text": "سُورَةُ ٱلْفَاتِحَةِ",
              "surah": "001"
            },
            {
              "line": 2,
              "type": "text",
              "text": "بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ ١",
              "verseRange": "1:1-1:1",
              "words": [
                {"location": "1:1:1", "word": "بِسْمِ", "qpcV2": "ﱁ", "qpcV1": "ﭑ"},
                {"location": "1:1:2", "word": "ٱللَّهِ", "qpcV2": "ﱂ", "qpcV1": "ﭒ"},
                {"location": "1:1:3", "word": "ٱلرَّحْمَـٰنِ", "qpcV2": "ﱃ", "qpcV1": "ﭓ"},
                {"location": "1:1:4", "word": "ٱلرَّحِيمِ ١", "qpcV2": "ﱄ ﱅ", "qpcV1": "ﭔ ﭕ"}
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let layout = try JSONDecoder().decode(QULPageLayout.self, from: json)
        #expect(layout.page == 1)
        #expect(layout.lines.count == 2)

        // Surah header
        let header = layout.lines[0]
        #expect(header.type == .surahHeader)
        #expect(header.surah == "001")

        // Text line
        let textLine = layout.lines[1]
        #expect(textLine.type == .text)
        #expect(textLine.words?.count == 4)

        // Word parsing
        let firstWord = textLine.words![0]
        #expect(firstWord.word == "بِسْمِ")
        #expect(firstWord.ayahRef == AyahRef(surah: 1, ayah: 1))
        #expect(firstWord.wordIndex == 1)
    }

    @Test func decodeBasmalaLine() throws {
        let json = """
        {
          "page": 2,
          "lines": [
            {
              "line": 2,
              "type": "basmala",
              "qpcV2": "ﭑﭒﭓ",
              "qpcV1": "#\\"!"
            }
          ]
        }
        """.data(using: .utf8)!

        let layout = try JSONDecoder().decode(QULPageLayout.self, from: json)
        #expect(layout.lines[0].type == .basmala)
        #expect(layout.lines[0].qpcV2 != nil)
    }

    @Test func wordAyahRefParsing() {
        let word = QULWord(location: "114:6:3", word: "test", qpcV2: nil, qpcV1: nil)
        #expect(word.ayahRef == AyahRef(surah: 114, ayah: 6))
        #expect(word.wordIndex == 3)
    }
}
