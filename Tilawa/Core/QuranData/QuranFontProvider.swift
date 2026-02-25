import CoreText
import UIKit

/// Manages loading and caching of Quran fonts.
/// Supports both the Unicode Hafs font and QPC V1 page-specific glyph fonts.
final class QuranFontProvider: @unchecked Sendable {
    static let shared = QuranFontProvider()

    static let maxFontSize = 23.0
    static let minFontSize = 16.0

    private let hafsFontName: String
    private let surahNameFontName: String
    private let surahHeaderFontName: String
    private var registeredQCFPages: Set<Int> = []
    private var qcfPostScriptNames: [Int: String] = [:]
    private let lock = NSLock()

    /// Unicode codepoints for surah header glyphs (index 0 = surah 1, index 113 = surah 114).
    /// Mapping from QUL: https://qul.tarteel.ai/resources/font/458
    static let surahHeaderCodepoints: [UInt16] = [
        // Surahs 1-10
        0xFC45, 0xFC46, 0xFC47, 0xFC4A, 0xFC4B, 0xFC4E, 0xFC4F, 0xFC51, 0xFC52, 0xFC53,
        // Surahs 11-20
        0xFC55, 0xFC56, 0xFC58, 0xFC5A, 0xFC5B, 0xFC5C, 0xFC5D, 0xFC5E, 0xFC61, 0xFC62,
        // Surahs 21-30
        0xFC64, 0xFB51, 0xFB52, 0xFB54, 0xFB55, 0xFB57, 0xFB58, 0xFB5A, 0xFB5B, 0xFB5D,
        // Surahs 31-40
        0xFB5E, 0xFB60, 0xFB61, 0xFB63, 0xFB64, 0xFB66, 0xFB67, 0xFB69, 0xFB6A, 0xFB6C,
        // Surahs 41-50
        0xFB6D, 0xFB6F, 0xFB70, 0xFB72, 0xFB73, 0xFB75, 0xFB76, 0xFB78, 0xFB79, 0xFB7B,
        // Surahs 51-60
        0xFB7C, 0xFB7E, 0xFB7F, 0xFB81, 0xFB82, 0xFB84, 0xFB85, 0xFB87, 0xFB88, 0xFB8A,
        // Surahs 61-70
        0xFB8B, 0xFB8D, 0xFB8E, 0xFB90, 0xFB91, 0xFB93, 0xFB94, 0xFB96, 0xFB97, 0xFB99,
        // Surahs 71-80
        0xFB9A, 0xFB9C, 0xFB9D, 0xFB9F, 0xFBA0, 0xFBA2, 0xFBA3, 0xFBA5, 0xFBA6, 0xFBA8,
        // Surahs 81-90
        0xFBA9, 0xFBAB, 0xFBAC, 0xFBAE, 0xFBAF, 0xFBB1, 0xFBB2, 0xFBB4, 0xFBB5, 0xFBB7,
        // Surahs 91-100
        0xFBB8, 0xFBBA, 0xFBBB, 0xFBBD, 0xFBBE, 0xFBC0, 0xFBC1, 0xFBD3, 0xFBD4, 0xFBD6,
        // Surahs 101-110
        0xFBD7, 0xFBD9, 0xFBDA, 0xFBDC, 0xFBDD, 0xFBDF, 0xFBE0, 0xFBE2, 0xFBE3, 0xFBE5,
        // Surahs 111-114
        0xFBE6, 0xFBE8, 0xFBE9, 0xFBEB,
    ]

    init() {
        // Register Hafs Unicode font
        if let fontURL = Bundle.main.url(forResource: "UthmanicHafs_V22",
                                          withExtension: "ttf") {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
            let discoveredName: String? = {
                guard let descs = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
                      let desc = descs.first else { return nil }
                return CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) as? String
            }()
            self.hafsFontName = discoveredName ?? "KFGQPC Uthmanic Script HAFS"
        } else {
            self.hafsFontName = "KFGQPC Uthmanic Script HAFS"
        }

        // Register surah name font (ligature-based)
        if let fontURL = Bundle.main.url(forResource: "surah-name-v2",
                                          withExtension: "ttf") {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
            let discoveredName: String? = {
                guard let descs = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
                      let desc = descs.first else { return nil }
                return CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) as? String
            }()
            self.surahNameFontName = discoveredName ?? "surah-name-v2"
        } else {
            self.surahNameFontName = "surah-name-v2"
        }

        // Register surah header font (ornamental frame + surah name glyphs)
        if let fontURL = Bundle.main.url(forResource: "QCF_SurahHeader_COLOR-Regular",
                                          withExtension: "ttf") {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
            let discoveredName: String? = {
                guard let descs = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
                      let desc = descs.first else { return nil }
                return CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) as? String
            }()
            self.surahHeaderFontName = discoveredName ?? "QCF_SurahHeader_COLOR"
        } else {
            self.surahHeaderFontName = "QCF_SurahHeader_COLOR"
        }
    }

    /// Testable initializer.
    init(fontName: String) {
        self.hafsFontName = fontName
        self.surahNameFontName = "surah-name-v2"
        self.surahHeaderFontName = "QCF_SurahHeader_COLOR"
    }

    /// Create a CTFont for the Unicode Hafs font (fallback).
    func hafsFont(size: CGFloat) -> CTFont {
        CTFontCreateWithName(hafsFontName as CFString, size, nil)
    }

    /// Create a CTFont for a specific Mushaf page using QPC V1 glyph fonts.
    /// Registers the font on first access.
    func qcfFont(page: Int, size: CGFloat) -> CTFont {
        registerQCFFont(page: page)

        lock.lock()
        let psName = qcfPostScriptNames[page]
        lock.unlock()

        let nameToUse = psName ?? qcfFontName(for: page)
        return CTFontCreateWithName(nameToUse as CFString, size, nil)
    }

    /// Register the QPC V1 font for a given page if not already registered.
    private func registerQCFFont(page: Int) {
        lock.lock()
        let alreadyRegistered = registeredQCFPages.contains(page)
        lock.unlock()
        guard !alreadyRegistered else { return }

        let fileName = String(format: "QCF_P%03d", page)
        let fontURL = Bundle.main.url(forResource: fileName, withExtension: "TTF")
            ?? Bundle.main.url(forResource: fileName, withExtension: "ttf")
        guard let fontURL else { return }

        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)

        let discoveredName = discoverPostScriptName(from: fontURL)

        lock.lock()
        registeredQCFPages.insert(page)
        if let name = discoveredName {
            qcfPostScriptNames[page] = name
        }
        lock.unlock()
    }

    private func discoverPostScriptName(from url: URL) -> String? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let desc = descriptors.first else {
            return nil
        }
        return CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) as? String
    }

    private func qcfFontName(for page: Int) -> String {
        String(format: "QCF_P%03d", page)
    }

    /// Create a CTFont for the surah name ligature font.
    func surahNameFont(size: CGFloat) -> CTFont {
        CTFontCreateWithName(surahNameFontName as CFString, size, nil)
    }

    /// Create a CTFont for the surah header font (ornamental frame + name).
    func surahHeaderFont(size: CGFloat) -> CTFont {
        CTFontCreateWithName(surahHeaderFontName as CFString, size, nil)
    }

    var registeredFontName: String { hafsFontName }
}
