import UIKit
import SwiftUI
import CoreText

/// Pure Quran text renderer using direct glyph path rendering.
/// Renders ONLY the Quran content (text lines, surah headers, basmala).
/// All UI chrome (background, borders, padding) is handled by SwiftUI.
final class MushafPageUIView: UIView {

    // MARK: - Public Configuration

    var pageLayout: QULPageLayout? { didSet { if pageLayout?.page != oldValue?.page { rebuildLayout() } } }
    var pageFont: CTFont? { didSet { rebuildLayout() } }
    var highlightedWord: WordLocation? { didSet { setNeedsDisplay() } }
    var highlightedAyah: AyahRef? { didSet { setNeedsDisplay() } }
    var highlightedAyahEnd: AyahRef? { didSet { setNeedsDisplay() } }
    var theme: MushafTheme = .standard { didSet { setNeedsDisplay() } }
    var centeredPage: Bool = false { didSet { rebuildLayout() } }
    var onWordTapped: ((WordLocation) -> Void)?

    // MARK: - Types

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

        let inset = Self.horizontalInset
        let availableWidth = bounds.width - 2 * inset
        let lineCount = layout.lines.count
        guard lineCount > 0, availableWidth > 0 else {
            lineLayouts = []
            setNeedsDisplay()
            return
        }

        let availableHeight = bounds.height
        let standardSlotCount = 15
        let baseLineHeight = availableHeight / CGFloat(standardSlotCount)

        // Build variable-height slot grid: headers get their actual glyph height,
        // remaining space is shared among non-header slots.
        var slotHeights = Array(repeating: baseLineHeight, count: standardSlotCount)
        for line in layout.lines where line.type == .surahHeader {
            let idx = line.line - 1
            guard idx >= 0, idx < standardSlotCount else { continue }
            let surahNum = Int(line.surah ?? "1") ?? 1
            let h = Self.headerGlyphHeight(surahNumber: surahNum, availableWidth: availableWidth)
            slotHeights[idx] = max(baseLineHeight, h + 4)
        }

        // Scale so total = availableHeight
        let totalHeight = slotHeights.reduce(0, +)
        if totalHeight > 0 {
            let scale = availableHeight / totalHeight
            slotHeights = slotHeights.map { $0 * scale }
        }

        // Cumulative Y positions
        var slotTops = Array(repeating: CGFloat(0), count: standardSlotCount)
        var cumY: CGFloat = 0
        for i in 0..<standardSlotCount {
            slotTops[i] = cumY
            cumY += slotHeights[i]
        }

        var layouts: [LineLayout] = []

        for line in layout.lines {
            let idx = line.line - 1
            guard idx >= 0, idx < standardSlotCount else { continue }
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
            }
        }

        ctx.restoreGState()
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
        // Adjust for horizontal inset used in rendering
        let adjustedPoint = CGPoint(x: point.x - Self.horizontalInset, y: point.y)
        for (lineIndex, lineLayout) in lineLayouts.enumerated() {
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
