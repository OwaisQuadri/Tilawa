import CoreText
import UIKit

/// Manages loading and caching of Quran fonts.
/// Supports both the Unicode Hafs font and QPC V1 page-specific glyph fonts.
final class QuranFontProvider: @unchecked Sendable {
    static let shared = QuranFontProvider()

    private let hafsFontName: String
    private let surahNameFontName: String
    private var registeredQCFPages: Set<Int> = []
    private var qcfPostScriptNames: [Int: String] = [:]
    private let lock = NSLock()

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
    }

    /// Testable initializer.
    init(fontName: String) {
        self.hafsFontName = fontName
        self.surahNameFontName = "surah-name-v2"
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

    var registeredFontName: String { hafsFontName }
}
