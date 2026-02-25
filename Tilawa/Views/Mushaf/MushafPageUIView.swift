import UIKit
import CoreText

/// Renders a single Mushaf page using direct glyph path rendering.
/// Text lines use CTFontCreatePathForGlyph with QPC V1 fonts, bypassing
/// CoreText's Arabic shaper which decomposes presentation form codepoints.
final class MushafPageUIView: UIView {

    // MARK: - Public Configuration

    var pageLayout: QULPageLayout? { didSet { if pageLayout?.page != oldValue?.page { rebuildLayout() } } }
    var pageFont: CTFont? { didSet { rebuildLayout() } }
    var highlightedWord: WordLocation? { didSet { setNeedsDisplay() } }
    var highlightedAyah: AyahRef? { didSet { setNeedsDisplay() } }
    var theme: MushafTheme = .light { didSet { setNeedsDisplay() } }
    var onWordTapped: ((WordLocation) -> Void)?

    // MARK: - Types

    /// Identifies a specific word on a page.
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

    /// Glyph data for a single word, used for direct rendering.
    private struct WordGlyphData {
        let glyphs: [CGGlyph]
        let advances: [CGSize]
        let totalAdvance: CGFloat
        let word: QULWord
    }

    /// Layout for a single line — either CTLine-based (headers) or glyph-based (text).
    private enum LineRenderMode {
        case ctLine(CTLine)
        case glyphs   // uses wordGlyphData from LineLayout
    }

    private struct LineLayout {
        let renderMode: LineRenderMode
        let origin: CGPoint          // baseline origin in view coords (top-left system)
        let lineRect: CGRect
        let words: [WordLayout]
        let lineInfo: QULLine
        let wordGlyphData: [WordGlyphData]  // only used for .glyphs mode
    }

    struct WordLayout {
        let rect: CGRect
        let word: QULWord
    }

    private var lineLayouts: [LineLayout] = []

    // MARK: - Layout Constants

    private let contentPadding: CGFloat = 8
    private let pageBorderWidth: CGFloat = 2

    // MARK: - Rebuild Layout

    private func rebuildLayout() {
        guard let layout = pageLayout, let font = pageFont else {
            lineLayouts = []
            setNeedsDisplay()
            return
        }

        let availableWidth = bounds.width
        let lineCount = layout.lines.count
        guard lineCount > 0, availableWidth > 0 else {
            lineLayouts = []
            setNeedsDisplay()
            return
        }

        let availableHeight = bounds.height
        // Use fixed line height based on standard 15-line Mushaf page.
        // Pages with fewer lines (e.g. pages 1-2) align to the top.
        let standardLineCount: CGFloat = 15
        let lineHeight = availableHeight / standardLineCount

        var layouts: [LineLayout] = []

        for (_, line) in layout.lines.enumerated() {
            let y = CGFloat(line.line - 1) * lineHeight + lineHeight * 0.7

            switch line.type {
            case .surahHeader:
                layouts.append(buildSurahHeaderLayout(line: line, font: font, y: y, availableWidth: availableWidth))
            case .basmala:
                layouts.append(buildBasmalaLayout(line: line, font: font, y: y, availableWidth: availableWidth, lineHeight: lineHeight))
            case .text:
                layouts.append(buildGlyphTextLayout(line: line, font: font, y: y, availableWidth: availableWidth, lineHeight: lineHeight))
            }
        }

        lineLayouts = layouts
        setNeedsDisplay()
    }

    // MARK: - Surah Header (surah-name-v2 ligature font)

    private func buildSurahHeaderLayout(line: QULLine, font: CTFont, y: CGFloat, availableWidth: CGFloat) -> LineLayout {
        let surahNumber = line.surah ?? "001"
        let ligatureText = "surah\(surahNumber)"

        // Compute line height to constrain frame within one slot
        let availableHeight = bounds.height
        let lineHeight = availableHeight / 15
        let framePadding: CGFloat = 4

        // Size the surah name font to fit within the line height
        let targetHeight = lineHeight - framePadding * 2
        let headerFontSize = targetHeight * 0.7
        let surahFont = QuranFontProvider.shared.surahNameFont(size: headerFontSize)

        let attrStr = NSAttributedString(string: ligatureText, attributes: [
            .font: surahFont as UIFont,
            .foregroundColor: theme.textColor,
            .ligature: 2  // enable all ligatures
        ])
        let ctLine = CTLineCreateWithAttributedString(attrStr)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        let x = (availableWidth) / 2

        // Frame constrained to one line height slot
        let frameY = y - lineHeight * 0.7
        let frameHeight = lineHeight

        return LineLayout(
            renderMode: .ctLine(ctLine),
            origin: CGPoint(x: x, y: y),
            lineRect: CGRect(x: 0, y: frameY, width: availableWidth, height: frameHeight),
            words: [],
            lineInfo: line,
            wordGlyphData: []
        )
    }

    // MARK: - Basmala (Hafs Unicode font with ﷽ ligature glyph)

    private func buildBasmalaLayout(line: QULLine, font: CTFont, y: CGFloat, availableWidth: CGFloat, lineHeight: CGFloat) -> LineLayout {
        let basmalaFontSize = CTFontGetSize(font) * 0.85
        let basmalaFont = QuranFontProvider.shared.hafsFont(size: basmalaFontSize)

        // U+FDFD — single basmala ligature glyph ﷽
        let basmalaText = "\u{FDFD}"

        let attrStr = NSAttributedString(string: basmalaText, attributes: [
            .font: basmalaFont as UIFont,
            .foregroundColor: theme.textColor
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

    // MARK: - Text Lines (Direct Glyph Rendering — bypasses CoreText shaping)

    private func buildGlyphTextLayout(line: QULLine, font: CTFont, y: CGFloat, availableWidth: CGFloat, lineHeight: CGFloat) -> LineLayout {
        guard let words = line.words, !words.isEmpty else {
            return LineLayout(
                renderMode: .glyphs,
                origin: CGPoint(x: 0, y: y),
                lineRect: .zero, words: [], lineInfo: line, wordGlyphData: []
            )
        }

        let fontSize = CTFontGetSize(font)

        // Step 1: Convert each word's qpcV1 codepoints to glyph IDs via direct cmap lookup
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

        // Step 2: Decide between justification and centering based on fill ratio
        let totalWordsWidth = wordGlyphs.reduce(0) { $0 + $1.totalAdvance }
        let gapCount = max(words.count - 1, 0)
        let fillRatio = availableWidth > 0 ? totalWordsWidth / availableWidth : 1

        let interWordSpacing: CGFloat
        let lineStartX: CGFloat

        if fillRatio > 0.75 && fillRatio <= 1.2 && words.count > 2 {
            // Justify: spread words across full available width (regular Mushaf lines)
            let spacing = gapCount > 0 ? (availableWidth - totalWordsWidth) / CGFloat(gapCount) : 0
            interWordSpacing = max(spacing, 0)  // prevent negative spacing
            lineStartX = 0
        } else {
            // Center: use natural word gap (pages 1-2, short lines, end of surahs, overflow)
            let naturalWordGap = fontSize * 0.25
            interWordSpacing = naturalWordGap
            let totalLineWidth = totalWordsWidth + naturalWordGap * CGFloat(gapCount)
            lineStartX = max((availableWidth - totalLineWidth) / 2, 0)
        }

        // Step 3: Position words RTL (right to left)
        let totalLineWidth = totalWordsWidth + interWordSpacing * CGFloat(gapCount)
        var wordLayouts: [WordLayout] = []
        var xCursor = lineStartX + totalLineWidth  // start from right edge

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

        // Background
        ctx.setFillColor(theme.backgroundColor.cgColor)
        ctx.fill(bounds)

        // Page side indicator (binding edge)
        drawPageSideIndicator(ctx)

        // Flip for CoreText (UIKit is top-left origin, CT is bottom-left)
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        for lineLayout in lineLayouts {
            // Draw decorative surah header frame
            if lineLayout.lineInfo.type == .surahHeader {
                let flippedRect = CGRect(
                    x: lineLayout.lineRect.origin.x,
                    y: bounds.height - lineLayout.lineRect.origin.y - lineLayout.lineRect.height,
                    width: lineLayout.lineRect.width,
                    height: lineLayout.lineRect.height
                )
                drawSurahHeaderFrame(in: ctx, rect: flippedRect)
            }

            // Draw word highlights
            for wordLayout in lineLayout.words {
                let shouldHighlightWord = highlightedWord.map {
                    $0.pageNumber == (pageLayout?.page ?? -1)
                    && wordLayout.word.location == $0.word.location
                } ?? false
                let shouldHighlightAyah = !shouldHighlightWord
                    && highlightedAyah == wordLayout.word.ayahRef

                if shouldHighlightWord || shouldHighlightAyah {
                    let color = shouldHighlightWord
                        ? theme.highlightColor.withAlphaComponent(0.5)
                        : theme.highlightColor
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

            // Draw the line content
            switch lineLayout.renderMode {
            case .ctLine(let ctLine):
                // Standard CTLine rendering for headers/fallback basmala
                let flippedY = bounds.height - lineLayout.origin.y
                ctx.textPosition = CGPoint(x: lineLayout.origin.x, y: flippedY)
                CTLineDraw(ctLine, ctx)

            case .glyphs:
                // Direct glyph rendering via CGPath — bypasses CoreText's Arabic shaper
                guard let font = pageFont else { break }

                let flippedBaselineY = bounds.height - lineLayout.origin.y
                ctx.setFillColor(theme.textColor.cgColor)

                for (wordIdx, glyphData) in lineLayout.wordGlyphData.enumerated() {
                    let wordRect = wordIdx < lineLayout.words.count
                        ? lineLayout.words[wordIdx].rect
                        : nil

                    let wordX = wordRect?.origin.x ?? lineLayout.origin.x

                    // Use the correct font for basmala lines
                    let drawFont: CTFont
                    if lineLayout.lineInfo.type == .basmala {
                        let basmalaSize = CTFontGetSize(font) * 0.85
                        drawFont = CTFontCreateCopyWithAttributes(font, basmalaSize, nil, nil)
                    } else {
                        drawFont = font
                    }

                    // Draw each glyph as a filled path (RTL: start from right edge, move left)
                    var xPos = wordX + glyphData.totalAdvance
                    for i in 0..<glyphData.glyphs.count {
                        xPos -= glyphData.advances[i].width
                        let glyph = glyphData.glyphs[i]
                        if let glyphPath = CTFontCreatePathForGlyph(drawFont, glyph, nil) {
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

    /// Draws a thin decorative border on the outer (binding) edge of the page.
    /// Odd pages: border on right. Even pages: border on left.
    private func drawPageSideIndicator(_ ctx: CGContext) {
        let pageNumber = pageLayout?.page ?? 1
        let isOddPage = pageNumber % 2 == 1

        let borderX: CGFloat = isOddPage
            ? bounds.width - pageBorderWidth
            : 0

        // Main border line
        ctx.setFillColor(theme.pageBorderColor.cgColor)
        ctx.fill(CGRect(x: borderX, y: 0, width: pageBorderWidth, height: bounds.height))

        // Subtle shadow gradient toward the binding edge
        let shadowWidth: CGFloat = 8
        let shadowX: CGFloat = isOddPage
            ? bounds.width - pageBorderWidth - shadowWidth
            : pageBorderWidth

        let startColor = theme.pageBorderColor.withAlphaComponent(0.5).cgColor
        let endColor = UIColor.clear.cgColor
        let colors = isOddPage ? [endColor, startColor] : [startColor, endColor]

        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors as CFArray,
                                         locations: nil) else { return }
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: shadowX, y: 0),
                               end: CGPoint(x: shadowX + shadowWidth, y: 0),
                               options: [])
    }

    /// Draws an ornamental frame around the surah header, inspired by the Madinah Mushaf cartouche.
    private func drawSurahHeaderFrame(in ctx: CGContext, rect: CGRect) {
        let inset: CGFloat = 4
        let outerRect = rect.insetBy(dx: inset, dy: 0)
        let innerRect = outerRect.insetBy(dx: 5, dy: 5)
        let cornerRadius: CGFloat = 8
        let innerCornerRadius: CGFloat = 4
        let borderColor = theme.pageBorderColor.cgColor
        let fillColor = theme.headerColor.cgColor

        // Outer rounded rect fill
        let outerPath = UIBezierPath(roundedRect: outerRect, cornerRadius: cornerRadius)
        ctx.setFillColor(fillColor)
        ctx.addPath(outerPath.cgPath)
        ctx.fillPath()

        // Outer border
        ctx.setStrokeColor(borderColor)
        ctx.setLineWidth(1.5)
        ctx.addPath(outerPath.cgPath)
        ctx.strokePath()

        // Inner border (double-border effect)
        let innerPath = UIBezierPath(roundedRect: innerRect, cornerRadius: innerCornerRadius)
        ctx.setLineWidth(0.75)
        ctx.addPath(innerPath.cgPath)
        ctx.strokePath()

        // Decorative diamonds at left and right center of the frame
        let diamondSize: CGFloat = 6
        let midY = outerRect.midY
        for x in [outerRect.minX + 12, outerRect.maxX - 12] {
            let diamond = UIBezierPath()
            diamond.move(to: CGPoint(x: x, y: midY - diamondSize))
            diamond.addLine(to: CGPoint(x: x + diamondSize, y: midY))
            diamond.addLine(to: CGPoint(x: x, y: midY + diamondSize))
            diamond.addLine(to: CGPoint(x: x - diamondSize, y: midY))
            diamond.close()
            ctx.setFillColor(borderColor)
            ctx.addPath(diamond.cgPath)
            ctx.fillPath()
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

    /// Find which word contains the given point.
    func wordAt(point: CGPoint) -> WordLocation? {
        guard let layout = pageLayout else { return nil }

        for (lineIndex, lineLayout) in lineLayouts.enumerated() {
            for (wordIndex, wordLayout) in lineLayout.words.enumerated() {
                let hitRect = wordLayout.rect.insetBy(dx: -4, dy: -4)
                if hitRect.contains(point) {
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
        rebuildLayout()
    }
}
