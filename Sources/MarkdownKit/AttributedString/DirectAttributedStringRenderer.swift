//
//  DirectAttributedStringRenderer.swift
//  MarkdownKit
//
//  Converts a MarkdownKit Block AST directly to NSAttributedString,
//  bypassing the HTML intermediate step for dramatically better performance.
//

#if os(iOS) || os(watchOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import Cocoa
#endif

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)

open class DirectAttributedStringRenderer {

  // MARK: - Style Configuration

  public struct StyleConfig {
    let baseFont: UIFont
    let baseFontSize: CGFloat
    let fontColor: UIColor

    let boldFont: UIFont
    let italicFont: UIFont
    let boldItalicFont: UIFont

    let h1Font: UIFont; let h1Color: UIColor
    let h1SpacingBefore: CGFloat; let h1SpacingAfter: CGFloat
    let h2Font: UIFont; let h2Color: UIColor
    let h2SpacingBefore: CGFloat; let h2SpacingAfter: CGFloat
    let h3Font: UIFont; let h3Color: UIColor
    let h3SpacingBefore: CGFloat; let h3SpacingAfter: CGFloat
    let h4Font: UIFont; let h4Color: UIColor
    let h4SpacingBefore: CGFloat; let h4SpacingAfter: CGFloat
    let h5Font: UIFont; let h5Color: UIColor
    let h5SpacingBefore: CGFloat; let h5SpacingAfter: CGFloat
    let h6Font: UIFont; let h6Color: UIColor
    let h6SpacingBefore: CGFloat; let h6SpacingAfter: CGFloat

    let codeFont: UIFont
    let codeFontColor: UIColor
    let codeBackground: UIColor

    let codeBlockFont: UIFont
    let codeBlockFontColor: UIColor
    let codeBlockBackground: UIColor

    let linkColor: UIColor
    let blockquoteColor: UIColor
    let blockquoteFont: UIFont
    let borderColor: UIColor

    let paragraphSpacing: CGFloat
    let listItemSpacing: CGFloat
    let listIndentPerLevel: CGFloat

    public init(fontSize: Float,
                fontFamily: String = "Helvetica Neue",
                fontColor: String = "#131B20",
                codeFontSize: Float? = nil,
                codeFontFamily: String = "Courier New",
                codeFontColor: String = "#333333",
                codeBlockFontSize: Float? = nil,
                codeBlockFontColor: String = "#333333",
                codeBlockBackground: String = "#f5f5f5",
                borderColor: String = "#cccccc",
                blockquoteColor: String = "#99c",
                h1Color: String = "#131B20",
                h2Color: String = "#131B20",
                h3Color: String = "#131B20",
                h4Color: String = "#131B20") {
      // No pxToPoints conversion — fontSize is used directly as points
      // (the 0.905 factor was only needed for ZMarkupParser's CSS rendering)
      let basePt = CGFloat(fontSize)
      let codePt = CGFloat(codeFontSize ?? (fontSize - 2))
      let codeBlockPt = CGFloat(codeBlockFontSize ?? (fontSize - 2))

      self.baseFontSize = basePt
      self.baseFont = UIFont(name: fontFamily, size: basePt)
                      ?? UIFont.systemFont(ofSize: basePt)
      self.fontColor = UIColor(hex: fontColor) ?? .black

      self.boldFont = UIFont(name: "\(fontFamily) Bold", size: basePt)
                      ?? UIFont.boldSystemFont(ofSize: basePt)
      self.italicFont = UIFont(name: "\(fontFamily) Italic", size: basePt)
                        ?? UIFont.italicSystemFont(ofSize: basePt)
      // Bold-italic: try named font, fallback to descriptor traits
      if let bi = UIFont(name: "\(fontFamily) Bold Italic", size: basePt) {
        self.boldItalicFont = bi
      } else {
        let desc = self.boldFont.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic])
                   ?? self.boldFont.fontDescriptor
        self.boldItalicFont = UIFont(descriptor: desc, size: basePt)
      }

      // Headings
      let h1Pt = CGFloat(fontSize + 6)
      let h2Pt = CGFloat(fontSize + 4)
      let h3Pt = CGFloat(fontSize + 2)
      let h4Pt = CGFloat(fontSize + 1)

      self.h1Font = UIFont(name: "\(fontFamily) Bold", size: h1Pt) ?? UIFont.boldSystemFont(ofSize: h1Pt)
      self.h1Color = UIColor(hex: h1Color) ?? .black
      self.h1SpacingBefore = 0; self.h1SpacingAfter = h1Pt * 0.5

      self.h2Font = UIFont(name: "\(fontFamily) Bold", size: h2Pt) ?? UIFont.boldSystemFont(ofSize: h2Pt)
      self.h2Color = UIColor(hex: h2Color) ?? .black
      self.h2SpacingBefore = 0; self.h2SpacingAfter = h2Pt * 0.4

      self.h3Font = UIFont(name: "\(fontFamily) Bold", size: h3Pt) ?? UIFont.boldSystemFont(ofSize: h3Pt)
      self.h3Color = UIColor(hex: h3Color) ?? .black
      self.h3SpacingBefore = 0; self.h3SpacingAfter = h3Pt * 0.3

      self.h4Font = UIFont(name: "\(fontFamily) Bold", size: h4Pt) ?? UIFont.boldSystemFont(ofSize: h4Pt)
      self.h4Color = UIColor(hex: h4Color) ?? .black
      self.h4SpacingBefore = 0; self.h4SpacingAfter = h4Pt * 0.2

      // H5: same size as base text, bold
      self.h5Font = UIFont(name: "\(fontFamily) Bold", size: basePt) ?? UIFont.boldSystemFont(ofSize: basePt)
      self.h5Color = UIColor(hex: h4Color) ?? .black
      self.h5SpacingBefore = 0; self.h5SpacingAfter = basePt * 0.15

      // H6: same size as base text, bold (same as H5 but with less spacing)
      self.h6Font = UIFont(name: "\(fontFamily) Bold", size: basePt) ?? UIFont.boldSystemFont(ofSize: basePt)
      self.h6Color = UIColor(hex: h4Color) ?? .black
      self.h6SpacingBefore = 0; self.h6SpacingAfter = basePt * 0.1

      // Code
      self.codeFont = UIFont(name: codeFontFamily, size: codePt) ?? UIFont.monospacedSystemFont(ofSize: codePt, weight: .regular)
      self.codeFontColor = UIColor(hex: codeFontColor) ?? .darkGray
      self.codeBackground = UIColor(hex: codeBlockBackground) ?? UIColor(white: 0.96, alpha: 1)

      self.codeBlockFont = UIFont(name: codeFontFamily, size: codeBlockPt) ?? UIFont.monospacedSystemFont(ofSize: codeBlockPt, weight: .regular)
      self.codeBlockFontColor = UIColor(hex: codeBlockFontColor) ?? .darkGray
      self.codeBlockBackground = UIColor(hex: codeBlockBackground) ?? UIColor(white: 0.96, alpha: 1)

      // Other
      self.linkColor = UIColor(hex: "#0000FF") ?? .blue
      self.blockquoteColor = UIColor(hex: blockquoteColor) ?? .gray
      self.blockquoteFont = UIFont(name: "\(fontFamily) Italic", size: basePt)
                            ?? UIFont.italicSystemFont(ofSize: basePt)
      self.borderColor = UIColor(hex: borderColor) ?? .gray

      self.paragraphSpacing = basePt * 0.7
      self.listItemSpacing = basePt * 0.1
      self.listIndentPerLevel = 20.0
    }
  }

  // MARK: - Custom Fragment Handler

  /// Closure to render custom text fragments from the app layer (e.g. LineEmphasis).
  /// Parameters: the custom fragment, base attributes, and a callback to render nested Text.
  public typealias CustomFragmentHandler = (
    CustomTextFragment,
    [NSAttributedString.Key: Any],
    (Text, [NSAttributedString.Key: Any]) -> NSMutableAttributedString
  ) -> NSMutableAttributedString?

  // MARK: - Properties

  public let config: StyleConfig
  public var customFragmentHandler: CustomFragmentHandler?

  /// Base attributes reused across all text rendering
  private let baseAttributes: [NSAttributedString.Key: Any]

  // MARK: - Init

  public init(config: StyleConfig, customFragmentHandler: CustomFragmentHandler? = nil) {
    self.config = config
    self.customFragmentHandler = customFragmentHandler
    self.baseAttributes = [
      .font: config.baseFont,
      .foregroundColor: config.fontColor
    ]
  }

  /// Convenience: create from the same parameters as AttributedStringGenerator
  public convenience init(fontSize: Float,
                          fontFamily: String = "Helvetica Neue",
                          fontColor: String = "#131B20",
                          codeFontSize: Float? = nil,
                          codeFontFamily: String = "Courier New",
                          codeFontColor: String = "#333333",
                          codeBlockFontSize: Float? = nil,
                          codeBlockFontColor: String = "#333333",
                          codeBlockBackground: String = "#f5f5f5",
                          borderColor: String = "#cccccc",
                          blockquoteColor: String = "#99c",
                          h1Color: String = "#131B20",
                          h2Color: String = "#131B20",
                          h3Color: String = "#131B20",
                          h4Color: String = "#131B20") {
    self.init(config: StyleConfig(fontSize: fontSize,
                                  fontFamily: fontFamily,
                                  fontColor: fontColor,
                                  codeFontSize: codeFontSize,
                                  codeFontFamily: codeFontFamily,
                                  codeFontColor: codeFontColor,
                                  codeBlockFontSize: codeBlockFontSize,
                                  codeBlockFontColor: codeBlockFontColor,
                                  codeBlockBackground: codeBlockBackground,
                                  borderColor: borderColor,
                                  blockquoteColor: blockquoteColor,
                                  h1Color: h1Color,
                                  h2Color: h2Color,
                                  h3Color: h3Color,
                                  h4Color: h4Color))
  }

  // MARK: - Public Entry Point

  public func render(doc: Block) -> NSAttributedString? {
    guard case .document(let blocks) = doc else { return nil }
    let result = renderBlocks(blocks, context: RenderContext())
    // Trim trailing newlines
    let str = result.string
    var end = str.endIndex
    while end > str.startIndex && str[str.index(before: end)] == "\n" {
      end = str.index(before: end)
    }
    if end < str.endIndex {
      result.deleteCharacters(in: NSRange(end..., in: str))
    }
    return result
  }

  // MARK: - Render Context

  private struct RenderContext {
    var listDepth: Int = 0
    var orderedListCounter: Int = 0
    var isOrdered: Bool = false
    var tight: Bool = false
    var inBlockquote: Bool = false
    var baseIndent: CGFloat = 0
  }

  // MARK: - Block Rendering

  private func renderBlocks(_ blocks: Blocks, context: RenderContext) -> NSMutableAttributedString {
    let result = NSMutableAttributedString()
    for block in blocks {
      result.append(renderBlock(block, context: context))
    }
    return result
  }

  private func renderBlock(_ block: Block, context: RenderContext) -> NSMutableAttributedString {
    switch block {
    case .document(let blocks):
      return renderBlocks(blocks, context: context)

    case .paragraph(let text):
      return renderParagraph(text, context: context)

    case .heading(let level, let text):
      return renderHeading(level: level, text: text, context: context)

    case .list(let start, let tight, let blocks):
      return renderList(start: start, tight: tight, blocks: blocks, context: context)

    case .listItem(let type, _, let blocks):
      return renderListItem(type: type, blocks: blocks, context: context)

    case .blockquote(let blocks):
      return renderBlockquote(blocks, context: context)

    case .fencedCode(_, let lines):
      return renderCodeBlock(lines: lines, context: context)

    case .indentedCode(let lines):
      return renderCodeBlock(lines: lines, context: context)

    case .thematicBreak:
      return renderThematicBreak(context: context)

    case .table(let header, let align, let rows):
      return renderTable(header: header, align: align, rows: rows, context: context)

    case .definitionList(let defs):
      return renderDefinitionList(defs, context: context)

    case .htmlBlock(let lines):
      // Render as plain text
      let text = lines.map { String($0) }.joined(separator: "\n")
      let result = NSMutableAttributedString(string: text + "\n", attributes: baseAttributes)
      return result

    case .referenceDef:
      return NSMutableAttributedString()

    case .custom(let customBlock):
      let text = customBlock.string
      return NSMutableAttributedString(string: text, attributes: baseAttributes)
    }
  }

  // MARK: - Paragraph

  private func renderParagraph(_ text: Text, context: RenderContext) -> NSMutableAttributedString {
    let result = renderText(text, baseAttributes: baseAttributes)
    result.append(NSAttributedString(string: "\n", attributes: baseAttributes))

    let paraStyle = makeParagraphStyle()
    if context.tight {
      paraStyle.paragraphSpacing = config.listItemSpacing
    } else {
      paraStyle.paragraphSpacing = config.paragraphSpacing
    }
    if context.baseIndent > 0 {
      paraStyle.firstLineHeadIndent = context.baseIndent
      paraStyle.headIndent = context.baseIndent
    }
    result.addAttribute(.paragraphStyle, value: paraStyle,
                        range: NSRange(location: 0, length: result.length))
    return result
  }

  // MARK: - Heading

  private func renderHeading(level: Int, text: Text, context: RenderContext) -> NSMutableAttributedString {
    let clampedLevel = max(1, min(level, 6))
    let font: UIFont
    let color: UIColor
    let spacingBefore: CGFloat
    let spacingAfter: CGFloat

    switch clampedLevel {
    case 1:
      font = config.h1Font; color = config.h1Color
      spacingBefore = config.h1SpacingBefore; spacingAfter = config.h1SpacingAfter
    case 2:
      font = config.h2Font; color = config.h2Color
      spacingBefore = config.h2SpacingBefore; spacingAfter = config.h2SpacingAfter
    case 3:
      font = config.h3Font; color = config.h3Color
      spacingBefore = config.h3SpacingBefore; spacingAfter = config.h3SpacingAfter
    case 4:
      font = config.h4Font; color = config.h4Color
      spacingBefore = config.h4SpacingBefore; spacingAfter = config.h4SpacingAfter
    case 5:
      font = config.h5Font; color = config.h5Color
      spacingBefore = config.h5SpacingBefore; spacingAfter = config.h5SpacingAfter
    default:
      font = config.h6Font; color = config.h6Color
      spacingBefore = config.h6SpacingBefore; spacingAfter = config.h6SpacingAfter
    }

    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color
    ]
    let result = renderText(text, baseAttributes: attrs)
    result.append(NSAttributedString(string: "\n", attributes: attrs))

    let paraStyle = makeParagraphStyle()
    paraStyle.paragraphSpacingBefore = spacingBefore
    paraStyle.paragraphSpacing = spacingAfter
    result.addAttribute(.paragraphStyle, value: paraStyle,
                        range: NSRange(location: 0, length: result.length))
    return result
  }

  // MARK: - List

  private func renderList(start: Int?, tight: Bool, blocks: Blocks, context: RenderContext) -> NSMutableAttributedString {
    var ctx = context
    ctx.listDepth = context.listDepth + 1
    ctx.tight = tight
    ctx.isOrdered = (start != nil)
    ctx.orderedListCounter = start ?? 1

    let result = NSMutableAttributedString()
    for block in blocks {
      if case .listItem(let type, let density, let innerBlocks) = block {
        result.append(renderListItem(type: type, blocks: innerBlocks, context: ctx))
        if ctx.isOrdered {
          ctx.orderedListCounter += 1
        }
      } else {
        result.append(renderBlock(block, context: ctx))
      }
    }

    // Add small spacer after top-level list (matching HTML generator's <p style="margin: 0;"/>)
    if context.listDepth == 0 {
      let spacer = NSMutableAttributedString(string: "\n", attributes: baseAttributes)
      let spacerStyle = makeParagraphStyle()
      spacerStyle.paragraphSpacing = 0
      spacerStyle.minimumLineHeight = 1
      spacerStyle.maximumLineHeight = 1
      spacer.addAttribute(.paragraphStyle, value: spacerStyle,
                          range: NSRange(location: 0, length: spacer.length))
      result.append(spacer)
    }

    return result
  }

  // MARK: - List Item

  private func renderListItem(type: ListType, blocks: Blocks, context: RenderContext) -> NSMutableAttributedString {
    let depth = context.listDepth

    // Match WebKit's NSTextList format: "\t•\ttext "
    let bulletChar: String
    switch type {
    case .bullet:
      // Level 1: disc ●, level 2: circle ○, level 3+: small square ▪
      if depth <= 1 {
        bulletChar = "\u{2022}"   // ● disc
      } else if depth == 2 {
        bulletChar = "\u{25E6}"   // ○ circle
      } else {
        bulletChar = "\u{2219}"   // ∙ bullet operator (smaller than •)
      }
    case .ordered:
      bulletChar = "\(context.orderedListCounter)."
    }
    let marker = "\t\(bulletChar)\t"

    // Diminishing indentation: full indent for first levels, progressively less for deeper ones.
    // This prevents deeply nested lists from overflowing the available width.
    // Levels 1-3: 36pt each, level 4: 24pt, level 5+: 16pt each, capped at 180pt total.
    let headIndent: CGFloat = {
      var indent: CGFloat = 0
      for level in 1...depth {
        if level <= 3 {
          indent += 36
        } else if level == 4 {
          indent += 24
        } else {
          indent += 16
        }
      }
      return min(indent, 180)
    }()

    // Paragraph style for list item — .left matches WebKit's NSTextList behavior
    let paraStyle = makeParagraphStyle(alignment: .left)
    paraStyle.firstLineHeadIndent = 0
    paraStyle.headIndent = headIndent
    paraStyle.tabStops = [
      NSTextTab(textAlignment: .right, location: headIndent - 12),
      NSTextTab(textAlignment: .left, location: headIndent)
    ]
    paraStyle.defaultTabInterval = 36
    paraStyle.paragraphSpacing = config.listItemSpacing

    let result = NSMutableAttributedString()

    // Start with the marker
    let markerStr = NSMutableAttributedString(string: marker, attributes: baseAttributes)
    result.append(markerStr)

    // Check if this item contains a nested list (affects trailing format)
    let hasNestedList = blocks.contains { if case .list = $0 { return true }; return false }

    // Render inner blocks
    for (index, innerBlock) in blocks.enumerated() {
      if case .paragraph(let text) = innerBlock {
        if index > 0 {
          // Continuation paragraph: use LINE SEPARATOR to stay in same NSAttributedString
          // paragraph (preserves headIndent alignment), matching WebKit's <br/> behavior
          result.append(NSAttributedString(string: " ", attributes: baseAttributes))
        }
        result.append(renderText(text, baseAttributes: baseAttributes))
      } else if case .blockquote(let quoteBlocks) = innerBlock {
        // Render blockquote inline as italic (matching InternalHtmlGenerator behavior)
        if index > 0 {
          result.append(NSAttributedString(string: " ", attributes: baseAttributes))
        }
        let quoteAttrs: [NSAttributedString.Key: Any] = [
          .font: config.blockquoteFont,
          .foregroundColor: config.blockquoteColor
        ]
        for (qi, quoteBlock) in quoteBlocks.enumerated() {
          if qi > 0 {
            result.append(NSAttributedString(string: " ", attributes: baseAttributes))
          }
          if case .paragraph(let text) = quoteBlock {
            result.append(renderText(text, baseAttributes: quoteAttrs))
          } else {
            result.append(renderBlock(quoteBlock, context: context))
          }
        }
      } else if case .list(let start, let tight, let nestedBlocks) = innerBlock {
        // Nested list: end current item line WITHOUT trailing space, then render nested list
        result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
        // Apply paragraph style to the current item content BEFORE appending nested list
        let itemLen = result.length
        result.addAttribute(.paragraphStyle, value: paraStyle,
                            range: NSRange(location: 0, length: itemLen))
        // Render nested list (its items will have their own paragraph styles)
        let nested = renderList(start: start, tight: tight, blocks: nestedBlocks, context: context)
        result.append(nested)
        return result
      } else {
        result.append(renderBlock(innerBlock, context: context))
      }
    }

    // Trailing space + line ending (matching WebKit's NSTextList output)
    result.append(NSAttributedString(string: " \n", attributes: baseAttributes))

    // Apply paragraph style to entire item
    result.addAttribute(.paragraphStyle, value: paraStyle,
                        range: NSRange(location: 0, length: result.length))

    return result
  }

  // MARK: - Blockquote

  private func renderBlockquote(_ blocks: Blocks, context: RenderContext) -> NSMutableAttributedString {
    var ctx = context
    ctx.inBlockquote = true
    ctx.baseIndent = context.baseIndent + 16

    let result = NSMutableAttributedString()
    for block in blocks {
      let rendered = renderBlock(block, context: ctx)
      // Apply blockquote styling
      let range = NSRange(location: 0, length: rendered.length)
      rendered.addAttribute(.foregroundColor, value: config.blockquoteColor, range: range)
      rendered.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
        if let font = value as? UIFont {
          let italicDesc = font.fontDescriptor.withSymbolicTraits(.traitItalic) ?? font.fontDescriptor
          let italicFont = UIFont(descriptor: italicDesc, size: font.pointSize)
          rendered.addAttribute(.font, value: italicFont, range: subRange)
        }
      }
      result.append(rendered)
    }

    // Apply indent via paragraph style
    result.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: result.length), options: []) { value, range, _ in
      let existing = (value as? NSParagraphStyle) ?? NSParagraphStyle.default
      let modified = existing.mutableCopy() as! NSMutableParagraphStyle
      modified.firstLineHeadIndent = max(modified.firstLineHeadIndent, ctx.baseIndent)
      modified.headIndent = max(modified.headIndent, ctx.baseIndent)
      result.addAttribute(.paragraphStyle, value: modified, range: range)
    }

    return result
  }

  // MARK: - Code Block

  private func renderCodeBlock(lines: Lines, context: RenderContext) -> NSMutableAttributedString {
    let code = lines.map { String($0) }.joined(separator: "\n")
    let attrs: [NSAttributedString.Key: Any] = [
      .font: config.codeBlockFont,
      .foregroundColor: config.codeBlockFontColor,
      .backgroundColor: config.codeBlockBackground
    ]
    let result = NSMutableAttributedString(string: code + "\n", attributes: attrs)

    let paraStyle = makeParagraphStyle()
    paraStyle.paragraphSpacing = config.paragraphSpacing
    if context.baseIndent > 0 {
      paraStyle.firstLineHeadIndent = context.baseIndent
      paraStyle.headIndent = context.baseIndent
    }
    result.addAttribute(.paragraphStyle, value: paraStyle,
                        range: NSRange(location: 0, length: result.length))
    return result
  }

  // MARK: - Thematic Break

  private func renderThematicBreak(context: RenderContext) -> NSMutableAttributedString {
    return NSMutableAttributedString()
  }

  // MARK: - Table

  private func renderTable(header: Row, align: Alignments, rows: Rows, context: RenderContext) -> NSMutableAttributedString {
    let result = NSMutableAttributedString()

    // Render header (bold)
    let headerAttrs: [NSAttributedString.Key: Any] = [
      .font: config.boldFont,
      .foregroundColor: config.fontColor
    ]
    for (i, cell) in header.enumerated() {
      if i > 0 {
        result.append(NSAttributedString(string: "\t", attributes: headerAttrs))
      }
      result.append(renderText(cell, baseAttributes: headerAttrs))
    }
    result.append(NSAttributedString(string: "\n", attributes: headerAttrs))

    // Render rows
    for row in rows {
      for (i, cell) in row.enumerated() {
        if i > 0 {
          result.append(NSAttributedString(string: "\t", attributes: baseAttributes))
        }
        result.append(renderText(cell, baseAttributes: baseAttributes))
      }
      result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
    }

    // Set up tab stops for columns
    let paraStyle = makeParagraphStyle()
    let columnCount = max(header.count, 1)
    let columnWidth: CGFloat = 100 // approximate
    var tabs: [NSTextTab] = []
    for col in 0..<columnCount {
      let alignment: NSTextAlignment
      if col < align.count {
        switch align[col] {
        case .left, .undefined: alignment = .left
        case .right: alignment = .right
        case .center: alignment = .center
        }
      } else {
        alignment = .left
      }
      tabs.append(NSTextTab(textAlignment: alignment, location: CGFloat(col) * columnWidth))
    }
    paraStyle.tabStops = tabs
    paraStyle.paragraphSpacing = config.listItemSpacing
    result.addAttribute(.paragraphStyle, value: paraStyle,
                        range: NSRange(location: 0, length: result.length))

    return result
  }

  // MARK: - Definition List

  private func renderDefinitionList(_ defs: Definitions, context: RenderContext) -> NSMutableAttributedString {
    let result = NSMutableAttributedString()

    for def in defs {
      // Term (bold)
      let termAttrs: [NSAttributedString.Key: Any] = [
        .font: config.boldFont,
        .foregroundColor: config.fontColor
      ]
      let term = renderText(def.item, baseAttributes: termAttrs)
      term.append(NSAttributedString(string: "\n", attributes: termAttrs))
      let termStyle = makeParagraphStyle()
      termStyle.paragraphSpacingBefore = config.baseFontSize * 0.6
      termStyle.paragraphSpacing = config.baseFontSize * 0.4
      term.addAttribute(.paragraphStyle, value: termStyle,
                        range: NSRange(location: 0, length: term.length))
      result.append(term)

      // Descriptions (indented)
      for descr in def.descriptions {
        if case .listItem(_, _, let blocks) = descr {
          var ctx = context
          ctx.baseIndent = 32 // 2em approximation
          for block in blocks {
            result.append(renderBlock(block, context: ctx))
          }
        }
      }
    }

    return result
  }

  // MARK: - Inline Text Rendering

  private func renderText(_ text: Text, baseAttributes attrs: [NSAttributedString.Key: Any]) -> NSMutableAttributedString {
    let result = NSMutableAttributedString()
    for fragment in text {
      result.append(renderFragment(fragment, baseAttributes: attrs))
    }
    return result
  }

  private func renderFragment(_ fragment: TextFragment, baseAttributes attrs: [NSAttributedString.Key: Any]) -> NSMutableAttributedString {
    switch fragment {
    case .text(let str):
      let decoded = String(str).decodingNamedCharacters()
      return NSMutableAttributedString(string: decoded, attributes: attrs)

    case .code(let str):
      var codeAttrs = attrs
      codeAttrs[.font] = config.codeFont
      codeAttrs[.foregroundColor] = config.codeFontColor
      codeAttrs[.backgroundColor] = config.codeBackground
      return NSMutableAttributedString(string: String(str), attributes: codeAttrs)

    case .emph(let text):
      var emphAttrs = attrs
      emphAttrs[.font] = deriveItalicFont(from: attrs[.font] as? UIFont)
      return renderText(text, baseAttributes: emphAttrs)

    case .strong(let text):
      var strongAttrs = attrs
      strongAttrs[.font] = deriveBoldFont(from: attrs[.font] as? UIFont)
      return renderText(text, baseAttributes: strongAttrs)

    case .link(let text, let uri, _):
      var linkAttrs = attrs
      linkAttrs[.foregroundColor] = config.linkColor
      linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
      if let uri = uri, let url = URL(string: uri) {
        linkAttrs[.link] = url
      }
      return renderText(text, baseAttributes: linkAttrs)

    case .autolink(let type, let str):
      var linkAttrs = attrs
      linkAttrs[.foregroundColor] = config.linkColor
      linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
      let urlStr = type == .email ? "mailto:\(str)" : String(str)
      if let url = URL(string: urlStr) {
        linkAttrs[.link] = url
      }
      return NSMutableAttributedString(string: String(str), attributes: linkAttrs)

    case .image(let text, _, _):
      // Render alt text as fallback (images are stripped by TextFormatter before reaching here)
      return renderText(text, baseAttributes: attrs)

    case .html:
      // Raw HTML tags — ignore
      return NSMutableAttributedString()

    case .delimiter(let ch, let n, _):
      // Unresolved delimiters — render as literal characters
      let str = String(repeating: ch, count: n)
      return NSMutableAttributedString(string: str, attributes: attrs)

    case .softLineBreak:
      return NSMutableAttributedString(string: " ", attributes: attrs)

    case .hardLineBreak:
      return NSMutableAttributedString(string: "\n", attributes: attrs)

    case .custom(let customFragment):
      return renderCustomFragment(customFragment, baseAttributes: attrs)
    }
  }

  // MARK: - Custom Fragment

  private func renderCustomFragment(_ fragment: CustomTextFragment, baseAttributes attrs: [NSAttributedString.Key: Any]) -> NSMutableAttributedString {
    // Delegate to the custom handler if provided
    if let handler = customFragmentHandler,
       let result = handler(fragment, attrs, { [weak self] text, attrs in
         self?.renderText(text, baseAttributes: attrs) ?? NSMutableAttributedString()
       }) {
      return result
    }
    // Fallback: render as plain text
    return NSMutableAttributedString(string: fragment.rawDescription, attributes: attrs)
  }

  // MARK: - Paragraph Style Helper

  /// Creates a paragraph style matching WebKit's default (.natural alignment).
  /// List items override to .left since NSTextList forces that.
  private func makeParagraphStyle(alignment: NSTextAlignment = .natural) -> NSMutableParagraphStyle {
    let ps = NSMutableParagraphStyle()
    ps.alignment = alignment
    return ps
  }

  // MARK: - Font Derivation Helpers

  private func deriveBoldFont(from font: UIFont?) -> UIFont {
    guard let font = font else { return config.boldFont }
    let traits = font.fontDescriptor.symbolicTraits
    if traits.contains(.traitItalic) {
      return config.boldItalicFont
    }
    // If it's a heading or other sized font, preserve the size
    if font.pointSize != config.baseFontSize {
      return UIFont(name: config.boldFont.fontName, size: font.pointSize)
             ?? UIFont.boldSystemFont(ofSize: font.pointSize)
    }
    return config.boldFont
  }

  private func deriveItalicFont(from font: UIFont?) -> UIFont {
    guard let font = font else { return config.italicFont }
    let traits = font.fontDescriptor.symbolicTraits
    if traits.contains(.traitBold) {
      return config.boldItalicFont
    }
    if font.pointSize != config.baseFontSize {
      return UIFont(name: config.italicFont.fontName, size: font.pointSize)
             ?? UIFont.italicSystemFont(ofSize: font.pointSize)
    }
    return config.italicFont
  }
}

// MARK: - UIColor hex init helper

private extension UIColor {
  convenience init?(hex: String) {
    var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if str.hasPrefix("#") { str.removeFirst() }
    guard str.count == 6, let rgb = UInt64(str, radix: 16) else { return nil }
    self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
              green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
              blue: CGFloat(rgb & 0xFF) / 255.0,
              alpha: 1.0)
  }
}

#endif
