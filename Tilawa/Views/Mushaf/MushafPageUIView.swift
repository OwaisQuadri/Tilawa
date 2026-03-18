import UIKit
import SwiftUI
import CoreText

/// Pure Quran text renderer using direct glyph path rendering.
/// Renders ONLY the Quran content (text lines, surah headers, basmala).
/// All UI chrome (background, borders, padding) is handled by SwiftUI.
final class MushafPageUIView: UIView {

    // MARK: - Public Configuration

    var pageLayout: QULPageLayout? { didSet { if pageLayout?.page != oldValue?.page { rebuildLayout() } } }
    var pageFont: CTFont? { didSet { if !fontsEqual(oldValue, pageFont) { rebuildLayout() } } }
    var highlightedWord: WordLocation? { didSet { if highlightedWord != oldValue { setNeedsDisplay() } } }
    var highlightedAyah: AyahRef? { didSet { if highlightedAyah != oldValue { setNeedsDisplay() } } }
    var highlightedAyahEnd: AyahRef? { didSet { if highlightedAyahEnd != oldValue { setNeedsDisplay() } } }
    var theme: MushafTheme = .standard { didSet { if theme != oldValue { setNeedsDisplay() } } }
    var centeredPage: Bool = false { didSet { if centeredPage != oldValue { rebuildLayout() } } }
    var riwayahContent: RiwayahPageContent? { didSet { rebuildLayout() } }
    var onWordTapped: ((WordLocation) -> Void)?

    // MARK: - Types

    /// Tracks which character range in the Unicode attributed string belongs to which ayah.
    struct UnicodeAyahMapping {
        let ayahRef: AyahRef
        let charRange: NSRange
    }

    struct WordLocation: Equatable {
        let pageNumber: Int
        let lineIndex: Int
        let wordIndex: Int
        let ayahRef: AyahRef
        let word: QULWord

        static func == (lhs: WordLocation, rhs: WordLocation) -> Bool {
            lhs.pageNumber == rhs.pageNumber
            && lhs.lineIndex == rhs.lineIndex
            && lhs.wordIndex == rhs.wordIndex
        }
    }

    // MARK: - Layout Cache

    private struct WordGlyphData {
        let glyphs: [CGGlyph]
        let advances: [CGSize]
        let totalAdvance: CGFloat
        let word: QULWord
    }

    private enum LineRenderMode {
        case ctLine(CTLine)
        case glyphs
        case surahHeader(glyph: CGGlyph, font: CTFont)
        /// Flowing Unicode text block for non-Hafs riwayahs. Contains a CTFrame,
        /// the rect it was typeset into (in CT coordinates: Y-up from view bottom),
        /// and per-ayah character range mappings for highlighting and hit-testing.
        case unicodeBlock(frame: CTFrame, frameRect: CGRect, ayahMappings: [UnicodeAyahMapping])
    }

    private struct LineLayout {
        let renderMode: LineRenderMode
        let origin: CGPoint
        let lineRect: CGRect
        let words: [WordLayout]
        let lineInfo: QULLine
        let wordGlyphData: [WordGlyphData]
    }

    struct WordLayout {
        let rect: CGRect
        let word: QULWord
    }

    private static func fontsEqual(_ a: CTFont?, _ b: CTFont?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (a?, b?):
            return CTFontGetSize(a) == CTFontGetSize(b)
                && CTFontCopyFullName(a) as String == CTFontCopyFullName(b) as String
        }
    }
    private func fontsEqual(_ a: CTFont?, _ b: CTFont?) -> Bool { Self.fontsEqual(a, b) }

    private var lineLayouts: [LineLayout] = []
    private var lastLayoutBounds: CGRect = .zero

    /// Horizontal inset to prevent glyph clipping at view edges.
    private static let horizontalInset: CGFloat = 0

    // MARK: - Rebuild Layout

    private func rebuildLayout() {
        guard let layout = pageLayout, let font = pageFont else {
            lineLayouts = []
            setNeedsDisplay()
            return
        }

        if let content = riwayahContent {
            rebuildUnicodeLayout(pageLayout: layout, font: font, content: content)
        } else {
            rebuildGlyphLayout(pageLayout: layout, font: font)
        }
    }

    /// Standard Hafs glyph-based layout (existing path).
    private func rebuildGlyphLayout(pageLayout layout: QULPageLayout, font: CTFont) {
        let inset = Self.horizontalInset
        let availableWidth = bounds.width - 2 * inset
        let lineCount = layout.lines.count
        guard lineCount > 0, availableWidth > 0 else {
            lineLayouts = []
            setNeedsDisplay()
            return
        }

        let (slotTops, slotHeights) = buildSlotGrid(layout: layout, availableWidth: availableWidth)
        var layouts: [LineLayout] = []

        for line in layout.lines {
            let idx = line.line - 1
            guard idx >= 0, idx < Self.standardSlotCount else { continue }
            let slotTop = slotTops[idx]
            let slotHeight = slotHeights[idx]
            let y = slotTop + slotHeight * 0.7

            switch line.type {
            case .surahHeader:
                layouts.append(buildSurahHeaderLayout(line: line, font: font, slotTop: slotTop, availableWidth: availableWidth, lineHeight: slotHeight))
            case .basmala:
                layouts.append(buildBasmalaLayout(line: line, font: font, y: y, availableWidth: availableWidth, lineHeight: slotHeight))
            case .text:
                layouts.append(buildGlyphTextLayout(line: line, font: font, y: y, availableWidth: availableWidth, lineHeight: slotHeight))
            }
        }

        lineLayouts = layouts
        setNeedsDisplay()
    }

    /// Calculate the content height for non-Hafs unicode rendering at the given width.
    func calculateContentHeight(for width: CGFloat) -> CGFloat {
        guard let font = pageFont, let content = riwayahContent, width > 0 else { return 0 }
        let fontSize = CTFontGetSize(font)
        var totalHeight: CGFloat = 0
        var pendingText: [RiwayahPageElement] = []

        func flushText() {
            guard !pendingText.isEmpty else { return }
            let (attrStr, _) = Self.buildRiwayahAttributedString(
                elements: pendingText, font: font, lineHeight: fontSize
            )
            guard attrStr.length > 0 else { pendingText = []; return }
            let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
            let size = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: 0), nil,
                CGSize(width: width, height: .greatestFiniteMagnitude), nil
            )
            totalHeight += size.height
            pendingText = []
        }

        for element in content.elements {
            switch element {
            case .surahHeader(let surahNumber):
                flushText()
                totalHeight += max(width / 7, Self.headerGlyphHeight(surahNumber: surahNumber, availableWidth: width) + 8)
            case .basmala:
                flushText()
                totalHeight += fontSize * 2
            case .ayahText:
                pendingText.append(element)
            }
        }
        flushText()
        return totalHeight + 16
    }

    /// Unicode CTFrame-based layout for non-Hafs riwayahs.
    /// Positions content sequentially (not using the fixed slot grid) so pages expand to fit.
    private func rebuildUnicodeLayout(pageLayout layout: QULPageLayout, font: CTFont, content: RiwayahPageContent) {
        let availableWidth = bounds.width
        guard availableWidth > 0, bounds.height > 0 else {
            lineLayouts = []
            setNeedsDisplay()
            return
        }

        var layouts: [LineLayout] = []
        var yPosition: CGFloat = 0
        var pendingText: [RiwayahPageElement] = []

        func flushTextElements() {
            guard !pendingText.isEmpty else { return }
            let fontSize = CTFontGetSize(font)
            let (attrStr, ayahMappings) = Self.buildRiwayahAttributedString(
                elements: pendingText, font: font, lineHeight: fontSize
            )
            guard attrStr.length > 0 else { pendingText = []; return }

            let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
            let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: 0), nil,
                CGSize(width: availableWidth, height: .greatestFiniteMagnitude), nil
            )
            let textHeight = suggestedSize.height

            // CT coordinates: Y-up from bottom of view
            let frameRect = CGRect(
                x: 0,
                y: bounds.height - yPosition - textHeight,
                width: availableWidth,
                height: textHeight
            )
            let path = CGPath(rect: frameRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)

            let dummyLine = QULLine(
                line: 1, type: .text,
                text: nil, surah: nil, verseRange: nil,
                words: nil, qpcV2: nil, qpcV1: nil
            )

            layouts.append(LineLayout(
                renderMode: .unicodeBlock(frame: frame, frameRect: frameRect, ayahMappings: ayahMappings),
                origin: CGPoint(x: 0, y: yPosition),
                lineRect: CGRect(x: 0, y: yPosition, width: availableWidth, height: textHeight),
                words: [],
                lineInfo: dummyLine,
                wordGlyphData: []
            ))

            yPosition += textHeight
            pendingText = []
        }

        for element in content.elements {
            switch element {
            case .surahHeader(let surahNumber):
                flushTextElements()
                let headerHeight = max(availableWidth / 7, Self.headerGlyphHeight(surahNumber: surahNumber, availableWidth: availableWidth) + 8)
                let dummyLine = QULLine(
                    line: 1, type: .surahHeader, text: nil,
                    surah: String(surahNumber), verseRange: nil,
                    words: nil, qpcV2: nil, qpcV1: nil
                )
                layouts.append(buildSurahHeaderLayout(
                    line: dummyLine, font: font, slotTop: yPosition,
                    availableWidth: availableWidth, lineHeight: headerHeight
                ))
                yPosition += headerHeight

            case .basmala:
                flushTextElements()
                let fontSize = CTFontGetSize(font)
                let basmalaHeight = fontSize * 2
                let baselineY = yPosition + basmalaHeight * 0.7
                let dummyLine = QULLine(
                    line: 1, type: .basmala, text: nil, surah: nil,
                    verseRange: nil, words: nil, qpcV2: nil, qpcV1: nil
                )
                layouts.append(buildBasmalaLayout(
                    line: dummyLine, font: font, y: baselineY,
                    availableWidth: availableWidth, lineHeight: basmalaHeight
                ))
                yPosition += basmalaHeight

            case .ayahText:
                pendingText.append(element)
            }
        }
        flushTextElements()

        lineLayouts = layouts
        setNeedsDisplay()
    }

    // MARK: - Slot Grid

    private static let standardSlotCount = 15

    /// Build the variable-height slot grid shared by both rendering paths.
    private func buildSlotGrid(layout: QULPageLayout, availableWidth: CGFloat) -> (slotTops: [CGFloat], slotHeights: [CGFloat]) {
        let availableHeight = bounds.height
        let baseLineHeight = availableHeight / CGFloat(Self.standardSlotCount)

        var slotHeights = Array(repeating: baseLineHeight, count: Self.standardSlotCount)
        for line in layout.lines where line.type == .surahHeader {
            let idx = line.line - 1
            guard idx >= 0, idx < Self.standardSlotCount else { continue }
            let surahNum = Int(line.surah ?? "1") ?? 1
            let h = Self.headerGlyphHeight(surahNumber: surahNum, availableWidth: availableWidth)
            slotHeights[idx] = max(baseLineHeight, h + 4)
        }

        let totalHeight = slotHeights.reduce(0, +)
        if totalHeight > 0 {
            let scale = availableHeight / totalHeight
            slotHeights = slotHeights.map { $0 * scale }
        }

        var slotTops = Array(repeating: CGFloat(0), count: Self.standardSlotCount)
        var cumY: CGFloat = 0
        for i in 0..<Self.standardSlotCount {
            slotTops[i] = cumY
            cumY += slotHeights[i]
        }

        return (slotTops, slotHeights)
    }

    // MARK: - Unicode Layout Helpers

    private struct TextSlotRegion {
        let startSlot: Int
        let endSlot: Int   // inclusive
    }

    /// Group consecutive ayahText elements, splitting at surahHeader/basmala boundaries.
    private static func groupAyahTextElements(_ elements: [RiwayahPageElement]) -> [[RiwayahPageElement]] {
        var groups: [[RiwayahPageElement]] = [[]]
        for element in elements {
            switch element {
            case .surahHeader, .basmala:
                if !(groups.last?.isEmpty ?? true) { groups.append([]) }
            case .ayahText:
                groups[groups.count - 1].append(element)
            }
        }
        if groups.last?.isEmpty == true { groups.removeLast() }
        return groups
    }

    /// Find contiguous runs of text slots (slots not used by headers/basmala).
    private static func findTextSlotRegions(slotCount: Int, nonTextSlots: Set<Int>) -> [TextSlotRegion] {
        var regions: [TextSlotRegion] = []
        var start: Int?

        for i in 0..<slotCount {
            if !nonTextSlots.contains(i) {
                if start == nil { start = i }
            } else {
                if let s = start {
                    regions.append(TextSlotRegion(startSlot: s, endSlot: i - 1))
                    start = nil
                }
            }
        }
        if let s = start {
            regions.append(TextSlotRegion(startSlot: s, endSlot: slotCount - 1))
        }
        return regions
    }

    /// Build an attributed string from ayahText elements with ayah-end markers.
    private static func buildRiwayahAttributedString(
        elements: [RiwayahPageElement],
        font: CTFont,
        lineHeight: CGFloat
    ) -> (NSAttributedString, [UnicodeAyahMapping]) {
        let str = NSMutableAttributedString()
        var mappings: [UnicodeAyahMapping] = []

        for element in elements {
            guard case .ayahText(let surah, let nativeAyah, let text) = element else { continue }
            let startIdx = str.length
            str.append(NSAttributedString(string: text))
            // Ayah end marker: end-of-ayah sign + number in Arabic-Indic digits.
            // Use non-breaking space (U+00A0) before the marker to keep it on the same line as the last word.
            let marker = "\u{00A0}\u{06DD}\(arabicIndicDigits(nativeAyah)) "
            str.append(NSAttributedString(string: marker))
            mappings.append(UnicodeAyahMapping(
                ayahRef: AyahRef(surah: surah, ayah: nativeAyah),
                charRange: NSRange(location: startIdx, length: str.length - startIdx)
            ))
        }

        guard str.length > 0 else { return (str, mappings) }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineHeightMultiple = 1.6

        let fullRange = NSRange(location: 0, length: str.length)
        str.addAttribute(.font, value: font as UIFont, range: fullRange)
        str.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        str.addAttribute(
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String),
            value: true,
            range: fullRange
        )

        return (str, mappings)
    }

    /// Convert an integer to Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩).
    private static func arabicIndicDigits(_ n: Int) -> String {
        let digits: [Character] = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
        return String(String(n).map { digits[Int(String($0))!] })
    }

    /// Compute the height of a surah header glyph when scaled to fill the available width.
    private static func headerGlyphHeight(surahNumber: Int, availableWidth: CGFloat) -> CGFloat {
        let codepoints = QuranFontProvider.surahHeaderCodepoints
        guard surahNumber >= 1, surahNumber <= codepoints.count else { return 0 }

        let refSize: CGFloat = 100
        let refFont = QuranFontProvider.shared.surahHeaderFont(size: refSize)
        var chars: [UInt16] = [codepoints[surahNumber - 1]]
        var glyphs = [CGGlyph](repeating: 0, count: 1)
        CTFontGetGlyphsForCharacters(refFont, &chars, &glyphs, 1)

        var advances = [CGSize](repeating: .zero, count: 1)
        CTFontGetAdvancesForGlyphs(refFont, .horizontal, &glyphs, &advances, 1)
        guard advances[0].width > 0 else { return 0 }

        var bboxes = [CGRect](repeating: .zero, count: 1)
        CTFontGetBoundingRectsForGlyphs(refFont, .horizontal, &glyphs, &bboxes, 1)

        let scale = availableWidth / advances[0].width
        return bboxes[0].height * scale
    }

    // MARK: - Surah Header

    private func buildSurahHeaderLayout(line: QULLine, font: CTFont, slotTop: CGFloat, availableWidth: CGFloat, lineHeight: CGFloat) -> LineLayout {
        let surahNumber = Int(line.surah ?? "1") ?? 1
        let codepoints = QuranFontProvider.surahHeaderCodepoints
        guard surahNumber >= 1, surahNumber <= codepoints.count else {
            return LineLayout(renderMode: .glyphs, origin: CGPoint(x: 0, y: slotTop),
                              lineRect: .zero, words: [], lineInfo: line, wordGlyphData: [])
        }

        // Get glyph from the surah header font at a reference size to measure
        let referenceFontSize: CGFloat = 100
        let referenceFont = QuranFontProvider.shared.surahHeaderFont(size: referenceFontSize)
        var chars: [UInt16] = [codepoints[surahNumber - 1]]
        var glyphs = [CGGlyph](repeating: 0, count: 1)
        CTFontGetGlyphsForCharacters(referenceFont, &chars, &glyphs, 1)

        // Measure glyph advance at reference size
        var advances = [CGSize](repeating: .zero, count: 1)
        CTFontGetAdvancesForGlyphs(referenceFont, .horizontal, &glyphs, &advances, 1)
        let refAdvance = advances[0].width
        guard refAdvance > 0 else {
            return LineLayout(renderMode: .glyphs, origin: CGPoint(x: 0, y: slotTop),
                              lineRect: .zero, words: [], lineInfo: line, wordGlyphData: [])
        }

        // Scale font to fill available width (slot height already accommodates the glyph)
        let finalFontSize = referenceFontSize * (availableWidth / refAdvance)
        let finalFont = QuranFontProvider.shared.surahHeaderFont(size: finalFontSize)
        CTFontGetGlyphsForCharacters(finalFont, &chars, &glyphs, 1)

        // Compute bounding rect for vertical centering within the (taller) slot
        var boundingRects = [CGRect](repeating: .zero, count: 1)
        CTFontGetBoundingRectsForGlyphs(finalFont, .horizontal, &glyphs, &boundingRects, 1)
        let bbox = boundingRects[0]

        // Center glyph vertically in the slot
        let baselineY = slotTop + (lineHeight - bbox.height) / 2 - bbox.origin.y

        return LineLayout(
            renderMode: .surahHeader(glyph: glyphs[0], font: finalFont),
            origin: CGPoint(x: 0, y: baselineY),
            lineRect: CGRect(x: 0, y: slotTop, width: availableWidth, height: lineHeight),
            words: [],
            lineInfo: line,
            wordGlyphData: []
        )
    }

    // MARK: - Basmala

    private func buildBasmalaLayout(line: QULLine, font: CTFont, y: CGFloat, availableWidth: CGFloat, lineHeight: CGFloat) -> LineLayout {
        let basmalaFontSize = CTFontGetSize(font) * 0.85
        let basmalaFont = QuranFontProvider.shared.hafsFont(size: basmalaFontSize)

        let basmalaText = "\u{FDFD}"

        let attrStr = NSAttributedString(string: basmalaText, attributes: [
            .font: basmalaFont as UIFont,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ])
        let ctLine = CTLineCreateWithAttributedString(attrStr)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        let x = (availableWidth - lineWidth) / 2

        return LineLayout(
            renderMode: .ctLine(ctLine),
            origin: CGPoint(x: x, y: y),
            lineRect: CGRect(x: 0, y: y - basmalaFontSize, width: availableWidth, height: lineHeight),
            words: [],
            lineInfo: line,
            wordGlyphData: []
        )
    }

    // MARK: - Text Lines (Direct Glyph Rendering)

    private func buildGlyphTextLayout(line: QULLine, font: CTFont, y: CGFloat, availableWidth: CGFloat, lineHeight: CGFloat) -> LineLayout {
        guard let words = line.words, !words.isEmpty else {
            return LineLayout(
                renderMode: .glyphs,
                origin: CGPoint(x: 0, y: y),
                lineRect: .zero, words: [], lineInfo: line, wordGlyphData: []
            )
        }

        let fontSize = CTFontGetSize(font)

        var wordGlyphs: [WordGlyphData] = []
        for word in words {
            let wordStr = word.qpcV1 ?? word.word
            var chars = Array(wordStr.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: chars.count)
            CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count)

            var advances = [CGSize](repeating: .zero, count: glyphs.count)
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advances, glyphs.count)
            let totalAdvance = advances.reduce(0) { $0 + $1.width }

            wordGlyphs.append(WordGlyphData(glyphs: glyphs, advances: advances, totalAdvance: totalAdvance, word: word))
        }

        let totalWordsWidth = wordGlyphs.reduce(0) { $0 + $1.totalAdvance }
        let gapCount = max(words.count - 1, 0)

        let interWordSpacing: CGFloat
        let lineStartX: CGFloat

        if !centeredPage && words.count > 2 {
            // QUL assigns words to lines for full-width justification
            let spacing = gapCount > 0 ? (availableWidth - totalWordsWidth) / CGFloat(gapCount) : 0
            interWordSpacing = max(spacing, 0)
            lineStartX = 0
        } else {
            // Centered pages or short lines (1-2 words): center with natural spacing
            let naturalWordGap = fontSize * 0
            interWordSpacing = naturalWordGap
            let totalLineWidth = totalWordsWidth + naturalWordGap * CGFloat(gapCount)
            lineStartX = max((availableWidth - totalLineWidth) / 2, 0)
        }

        let totalLineWidth = totalWordsWidth + interWordSpacing * CGFloat(gapCount)
        var wordLayouts: [WordLayout] = []
        var xCursor = lineStartX + totalLineWidth

        for glyphData in wordGlyphs {
            xCursor -= glyphData.totalAdvance
            let wordRect = CGRect(
                x: xCursor,
                y: y - fontSize * 0.8,
                width: glyphData.totalAdvance,
                height: lineHeight
            )
            wordLayouts.append(WordLayout(rect: wordRect, word: glyphData.word))
            xCursor -= interWordSpacing
        }

        return LineLayout(
            renderMode: .glyphs,
            origin: CGPoint(x: lineStartX, y: y),
            lineRect: CGRect(x: 0, y: y - fontSize, width: availableWidth, height: lineHeight),
            words: wordLayouts,
            lineInfo: line,
            wordGlyphData: wordGlyphs
        )
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: Self.horizontalInset, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        for lineLayout in lineLayouts {
            // Word highlights
            for wordLayout in lineLayout.words {
                let shouldHighlightWord = highlightedWord.map {
                    $0.pageNumber == (pageLayout?.page ?? -1)
                    && wordLayout.word.location == $0.word.location
                } ?? false
                let wordRef = wordLayout.word.ayahRef
                let shouldHighlightAyah = !shouldHighlightWord
                    && highlightedAyah.map { start in
                        wordRef >= start && wordRef <= (highlightedAyahEnd ?? start)
                    } ?? false

                if shouldHighlightWord || shouldHighlightAyah {
                    let color = shouldHighlightWord
                        ? UIColor(theme.highlightColor).resolvedColor(with: traitCollection).withAlphaComponent(0.5)
                        : UIColor(theme.highlightColor).resolvedColor(with: traitCollection)
                    ctx.setFillColor(color.cgColor)
                    let flippedRect = CGRect(
                        x: wordLayout.rect.origin.x,
                        y: bounds.height - wordLayout.rect.origin.y - wordLayout.rect.height,
                        width: wordLayout.rect.width,
                        height: wordLayout.rect.height
                    )
                    let path = UIBezierPath(roundedRect: flippedRect.insetBy(dx: -2, dy: -1), cornerRadius: 3)
                    ctx.addPath(path.cgPath)
                    ctx.fillPath()
                }
            }

            // Line content
            switch lineLayout.renderMode {
            case .ctLine(let ctLine):
                let flippedY = bounds.height - lineLayout.origin.y
                ctx.setFillColor(UIColor(theme.textColor).resolvedColor(with: traitCollection).cgColor)
                ctx.textPosition = CGPoint(x: lineLayout.origin.x, y: flippedY)
                CTLineDraw(ctLine, ctx)

            case .surahHeader(let glyph, let headerFont):
                let flippedBaselineY = bounds.height - lineLayout.origin.y
                ctx.setFillColor(UIColor(theme.textColor).resolvedColor(with: traitCollection).cgColor)
                if let glyphPath = CTFontCreatePathForGlyph(headerFont, glyph, nil) {
                    var transform = CGAffineTransform(translationX: lineLayout.origin.x, y: flippedBaselineY)
                    if let movedPath = glyphPath.copy(using: &transform) {
                        ctx.addPath(movedPath)
                        ctx.fillPath()
                    }
                }

            case .glyphs:
                guard let font = pageFont else { break }

                let flippedBaselineY = bounds.height - lineLayout.origin.y
                ctx.setFillColor(UIColor(theme.textColor).resolvedColor(with: traitCollection).cgColor)

                for (wordIdx, glyphData) in lineLayout.wordGlyphData.enumerated() {
                    let wordX = wordIdx < lineLayout.words.count
                        ? lineLayout.words[wordIdx].rect.origin.x
                        : lineLayout.origin.x

                    let drawFont = font

                    var xPos = wordX + glyphData.totalAdvance
                    for i in 0..<glyphData.glyphs.count {
                        xPos -= glyphData.advances[i].width
                        if let glyphPath = CTFontCreatePathForGlyph(drawFont, glyphData.glyphs[i], nil) {
                            var transform = CGAffineTransform(translationX: xPos, y: flippedBaselineY)
                            if let movedPath = glyphPath.copy(using: &transform) {
                                ctx.addPath(movedPath)
                                ctx.fillPath()
                            }
                        }
                    }
                }

            case .unicodeBlock(let frame, let frameRect, let ayahMappings):
                // Draw highlights for the active ayah
                if let highlighted = highlightedAyah {
                    drawUnicodeHighlights(
                        ctx: ctx, frame: frame, frameRect: frameRect,
                        ayahMappings: ayahMappings,
                        highlighted: highlighted, end: highlightedAyahEnd
                    )
                }
                // Draw the flowing text
                ctx.setFillColor(UIColor(theme.textColor).resolvedColor(with: traitCollection).cgColor)
                CTFrameDraw(frame, ctx)
            }
        }

        ctx.restoreGState()
    }

    // MARK: - Unicode Highlight Drawing

    /// Draw highlight rectangles behind the specified ayah range within a CTFrame.
    private func drawUnicodeHighlights(
        ctx: CGContext,
        frame: CTFrame,
        frameRect: CGRect,
        ayahMappings: [UnicodeAyahMapping],
        highlighted: AyahRef,
        end: AyahRef?
    ) {
        let endRef = end ?? highlighted
        let highlightColor = UIColor(theme.highlightColor).resolvedColor(with: traitCollection)
        ctx.setFillColor(highlightColor.cgColor)

        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        for mapping in ayahMappings {
            guard mapping.ayahRef >= highlighted && mapping.ayahRef <= endRef else { continue }

            for (i, line) in lines.enumerated() {
                let lineRange = CTLineGetStringRange(line)
                let lineNSRange = NSRange(location: lineRange.location, length: lineRange.length)

                // Check if this line overlaps with the ayah's character range
                let overlap = NSIntersectionRange(lineNSRange, mapping.charRange)
                guard overlap.length > 0 else { continue }

                // Get x offsets for the overlapping range
                var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

                let startOffset = CTLineGetOffsetForStringIndex(line, overlap.location, nil)
                let endOffset = CTLineGetOffsetForStringIndex(line, overlap.location + overlap.length, nil)

                let minX = min(startOffset, endOffset)
                let maxX = max(startOffset, endOffset)
                let lineOrigin = CGPoint(
                    x: frameRect.origin.x + origins[i].x,
                    y: frameRect.origin.y + origins[i].y
                )

                let highlightRect = CGRect(
                    x: lineOrigin.x + minX,
                    y: lineOrigin.y - descent,
                    width: maxX - minX,
                    height: ascent + descent
                ).insetBy(dx: -2, dy: -1)

                let path = UIBezierPath(roundedRect: highlightRect, cornerRadius: 3)
                ctx.addPath(path.cgPath)
                ctx.fillPath()
            }
        }
    }

    // MARK: - Hit Testing

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        if let wordLocation = wordAt(point: point) {
            onWordTapped?(wordLocation)
        }
    }

    func wordAt(point: CGPoint) -> WordLocation? {
        guard let layout = pageLayout else { return nil }
        let adjustedPoint = CGPoint(x: point.x - Self.horizontalInset, y: point.y)

        for (lineIndex, lineLayout) in lineLayouts.enumerated() {
            // Standard word-level hit testing (Hafs glyph path)
            for (wordIndex, wordLayout) in lineLayout.words.enumerated() {
                let hitRect = wordLayout.rect.insetBy(dx: -4, dy: -4)
                if hitRect.contains(adjustedPoint) {
                    return WordLocation(
                        pageNumber: layout.page,
                        lineIndex: lineIndex,
                        wordIndex: wordIndex,
                        ayahRef: wordLayout.word.ayahRef,
                        word: wordLayout.word
                    )
                }
            }

            // Unicode block hit testing (non-Hafs riwayah path)
            if case .unicodeBlock(let frame, let frameRect, let ayahMappings) = lineLayout.renderMode {
                // Check if point is in the frame's view-coordinate rect
                let viewRect = lineLayout.lineRect
                guard viewRect.insetBy(dx: -4, dy: -4).contains(adjustedPoint) else { continue }

                // Convert point to CT coordinates (Y-up from view bottom)
                let ctPoint = CGPoint(x: adjustedPoint.x - frameRect.origin.x,
                                      y: bounds.height - adjustedPoint.y - frameRect.origin.y)

                let lines = CTFrameGetLines(frame) as! [CTLine]
                var origins = [CGPoint](repeating: .zero, count: lines.count)
                CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

                for (i, ctLine) in lines.enumerated() {
                    var ascent: CGFloat = 0, descent: CGFloat = 0
                    let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, nil))
                    let lineOrigin = origins[i]

                    let lineRect = CGRect(
                        x: lineOrigin.x,
                        y: lineOrigin.y - descent,
                        width: lineWidth,
                        height: ascent + descent
                    ).insetBy(dx: -4, dy: -4)

                    guard lineRect.contains(ctPoint) else { continue }

                    let relativePoint = CGPoint(x: ctPoint.x - lineOrigin.x, y: ctPoint.y - lineOrigin.y)
                    let stringIndex = CTLineGetStringIndexForPosition(ctLine, relativePoint)
                    guard stringIndex != kCFNotFound else { continue }

                    // Find which ayah this string index belongs to
                    for mapping in ayahMappings {
                        if NSLocationInRange(stringIndex, mapping.charRange) {
                            let syntheticWord = QULWord(
                                location: "\(mapping.ayahRef.surah):\(mapping.ayahRef.ayah):1",
                                word: "", qpcV2: nil, qpcV1: nil
                            )
                            return WordLocation(
                                pageNumber: layout.page,
                                lineIndex: lineIndex,
                                wordIndex: 0,
                                ayahRef: mapping.ayahRef,
                                word: syntheticWord
                            )
                        }
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds != lastLayoutBounds else { return }
        lastLayoutBounds = bounds
        rebuildLayout()
    }
}
