//
//  AttributedStringGenerator.swift
//  MarkdownKit
//
//  Created by Matthias Zenger on 01/08/2019.
//  Copyright © 2019-2021 Google LLC.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#if os(iOS) || os(watchOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import Cocoa
#endif
import ZMarkupParser

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)

///
/// `AttributedStringGenerator` provides functionality for converting Markdown blocks into
/// `NSAttributedString` objects that are used in macOS and iOS for displaying rich text.
/// The implementation is extensible allowing subclasses of `AttributedStringGenerator` to
/// override how individual Markdown structures are converted into attributed strings.
///
open class AttributedStringGenerator {
  
  /// Options for the attributed string generator
  public struct Options: OptionSet {
    public let rawValue: UInt
    
    public init(rawValue: UInt) {
      self.rawValue = rawValue
    }
    
    public static let tightLists = Options(rawValue: 1 << 0)
  }
  
  /// Customized html generator to work around limitations of the current HTML to
  /// `NSAttributedString` conversion logic provided by the operating system.
  open class InternalHtmlGenerator: HtmlGenerator {
    var outer: AttributedStringGenerator
    
    public init(outer: AttributedStringGenerator) {
      self.outer = outer
    }

    open override func generate(block: Block, parent: Parent, tight: Bool = false) -> String {
      switch block {
        case .list(let start, let tight, let blocks):
          let isNested = { () -> Bool in
            if case .block(.listItem(_, _, _), _) = parent { return true }
            return false
          }()
          let nestingDepth = { () -> Int in
            var depth = 0
            var current = parent
            while case .block(let b, let next) = current {
              if case .list(_, _, _) = b { depth += 1 }
              current = next
            }
            return depth
          }()
          let listContent = self.generate(blocks: blocks, parent: .block(block, parent), tight: tight)
          let res: String
          if let startNumber = start {
            res = "<ol start=\"\(startNumber)\">\n" + listContent + "</ol>\n"
          } else if isNested {
            let bulletStyle: String
            switch nestingDepth % 2 {
            case 1:  bulletStyle = "circle"   // ○
            default: bulletStyle = "disc"     // ●
            }
            res = "<ul style=\"list-style-type: \(bulletStyle)\">\n" + listContent + "</ul>\n"
          } else {
            res = "<ul>\n" + listContent + "</ul>\n"
          }
          return isNested ? res : res + "<p style=\"margin: 0;\" />\n"
        case .listItem(_, _, let blocks):
          var html = "<li>"
          for (index, innerBlock) in blocks.enumerated() {
            if case .paragraph(let text) = innerBlock {
              if index > 0 {
                html += "<br/>"
              }
              html += self.generate(text: text) + "\n"
            } else if case .blockquote(let quoteBlocks) = innerBlock {
              // Render blockquote content inline with italic styling instead of
              // block-level <blockquote> to avoid line break after bullet
              if index > 0 {
                html += "<br/>"
              }
              for (qi, quoteBlock) in quoteBlocks.enumerated() {
                if qi > 0 { html += "<br/>" }
                if case .paragraph(let text) = quoteBlock {
                  html += "<em>" + self.generate(text: text) + "</em>"
                } else {
                  html += self.generate(block: quoteBlock, parent: .block(block, parent), tight: true)
                }
              }
              html += "\n"
            } else {
              html += self.generate(block: innerBlock, parent: .block(block, parent), tight: false)
            }
          }
          html += "</li>\n"
          return html
        case .paragraph(let text):
          if case .block(.listItem(_, _, _), .block(.list(_, let tight, _), _)) = parent, tight {
            return self.generate(text: text) + "\n"
          } else {
            return "<p>" + self.generate(text: text) + "</p>\n"
          }
        case .indentedCode(_),
             .fencedCode(_, _):
          return "<table style=\"width: 100%; margin-bottom: 3px;\"><tbody><tr>" +
                 "<td class=\"codebox\">" +
                 super.generate(block: block, parent: .block(block, parent), tight: tight) +
                 "</td></tr></tbody></table><p style=\"margin: 0;\" />\n"
        case .blockquote(let blocks):
          return "<blockquote>\n" +
                 self.generate(blocks: blocks, parent: .block(block, parent)) +
                 "</blockquote>\n"
        case .thematicBreak:
          return "<p><table style=\"width: 100%; margin-bottom: 3px;\"><tbody>" +
                 "<tr><td class=\"thematic\"></td></tr></tbody></table></p>\n"
        case .table(let header, let align, let rows):
          var tagsuffix: [String] = []
          for a in align {
            switch a {
              case .undefined:
                tagsuffix.append(">")
              case .left:
                tagsuffix.append(" align=\"left\">")
              case .right:
                tagsuffix.append(" align=\"right\">")
              case .center:
                tagsuffix.append(" align=\"center\">")
            }
          }
          var html = "<table class=\"mtable\" " +
                     "cellpadding=\"\(self.outer.tableCellPadding)\"><thead><tr>\n"
          var i = 0
          for head in header {
            html += "<th\(tagsuffix[i])\(self.generate(text: head))&nbsp;</th>"
            i += 1
          }
          html += "\n</tr></thead><tbody>\n"
          for row in rows {
            html += "<tr>"
            i = 0
            for cell in row {
              html += "<td\(tagsuffix[i])\(self.generate(text: cell))&nbsp;</td>"
              i += 1
            }
            html += "</tr>\n"
          }
          html += "</tbody></table><p style=\"margin: 0;\" />\n"
          return html
        case .definitionList(let defs):
          var html = "<dl>\n"
          for def in defs {
            html += "<dt>" + self.generate(text: def.item) + "</dt>\n"
            for descr in def.descriptions {
              if case .listItem(_, _, let blocks) = descr {
                html += "<dd>" +
                        self.generate(blocks: blocks, parent: .block(block, parent)) +
                        "</dd>\n"
              }
            }
          }
          html += "</dl>\n"
          return html
        case .custom(let customBlock):
          return customBlock.generateHtml(via: self, and: self.outer, tight: tight)
        default:
          return super.generate(block: block, parent: parent, tight: tight)
      }
    }
    
    open override func generate(textFragment fragment: TextFragment) -> String {
      switch fragment {
        case .image(let text, let uri, let title):
          let titleAttr = title == nil ? "" : " title=\"\(title!)\""
          if let uriStr = uri {
            let url = URL(string: uriStr)
            if (url?.scheme == nil) || (url?.isFileURL ?? false),
               let baseUrl = self.outer.imageBaseUrl {
              let url = URL(fileURLWithPath: uriStr, relativeTo: baseUrl)
              if url.isFileURL {
                return "<img src=\"\(url.absoluteString)\"" +
                       " alt=\"\(text.rawDescription)\"\(titleAttr)/>"
              }
            }
            return "<img src=\"\(uriStr)\" alt=\"\(text.rawDescription)\"\(titleAttr)/>"
          } else {
            return self.generate(text: text)
          }
        case .custom(let customTextFragment):
          return customTextFragment.generateHtml(via: self, and: self.outer)
        default:
          return super.generate(textFragment: fragment)
      }
    }
  }

  /// HTML to NSAttributedString rendering backend.
  public enum HTMLRenderer {
    /// Uses NSAttributedString(data:options:.html) which internally calls WebKit.
    /// WARNING: Spins a nested run loop via NSHTMLReader._loadUsingWebKit, which can
    /// cause reentrancy crashes in UITableView._updateVisibleCellsNow:.
    /// Not safe to use during cell configuration in UITableView.
    case webKit

    /// Uses ZMarkupParser (pure Swift, synchronous, no WebKit, no run loop issues).
    case zMarkupParser

    /// Direct AST → NSAttributedString rendering, bypassing HTML entirely.
    /// Fastest and safest option.
    case direct
  }

  /// Default `AttributedStringGenerator` implementation.
  public static let standard: AttributedStringGenerator = AttributedStringGenerator()

  /// The HTML rendering backend.
  public let htmlRenderer: HTMLRenderer

  /// The generator options.
  public let options: Options
  
  /// The base font size.
  public let fontSize: Float

  /// The base font family.
  public let fontFamily: String

  /// The base font color.
  public let fontColor: String

  /// The code font size.
  public let codeFontSize: Float

  /// The code font family.
  public let codeFontFamily: String

  /// The code font color.
  public let codeFontColor: String

  /// The code block font size.
  public let codeBlockFontSize: Float

  /// The code block font color.
  public let codeBlockFontColor: String

  /// The code block background color.
  public let codeBlockBackground: String

  /// The border color (used for code blocks and for thematic breaks).
  public let borderColor: String

  /// The blockquote color.
  public let blockquoteColor: String

  /// The color of H1 headers.
  public let h1Color: String

  /// The color of H2 headers.
  public let h2Color: String

  /// The color of H3 headers.
  public let h3Color: String

  /// The color of H4 headers.
  public let h4Color: String

  /// The maximum width of an image
  public let maxImageWidth: String?
  
  /// The maximum height of an image
  public let maxImageHeight: String?
  
  /// Custom CSS style
  public let customStyle: String
  
  /// If provided, this URL is used as a base URL for relative image links
  public let imageBaseUrl: URL?
  
  
  /// Constructor providing customization options for the generated `NSAttributedString` markup.
  public init(htmlRenderer: HTMLRenderer = .zMarkupParser,
              options: Options = [],
              fontSize: Float = 14.0,
              fontFamily: String = "\"Times New Roman\",Times,serif",
              fontColor: String = mdDefaultColor,
              codeFontSize: Float = 13.0,
              codeFontFamily: String =
                                "\"Consolas\",\"Andale Mono\",\"Courier New\",Courier,monospace",
              codeFontColor: String = mdDefaultColor,
              codeBlockFontSize: Float = 12.0,
              codeBlockFontColor: String = mdDefaultColor,
              codeBlockBackground: String = mdDefaultBackgroundColor,
              borderColor: String = "#bbb",
              blockquoteColor: String = "#99c",
              h1Color: String = mdDefaultColor,
              h2Color: String = mdDefaultColor,
              h3Color: String = mdDefaultColor,
              h4Color: String = mdDefaultColor,
              maxImageWidth: String? = nil,
              maxImageHeight: String? = nil,
              customStyle: String = "",
              imageBaseUrl: URL? = nil) {
    self.htmlRenderer = htmlRenderer
    self.options = options
    self.fontSize = fontSize
    self.fontFamily = fontFamily
    self.fontColor = fontColor
    self.codeFontSize = codeFontSize
    self.codeFontFamily = codeFontFamily
    self.codeFontColor = codeFontColor
    self.codeBlockFontSize = codeBlockFontSize
    self.codeBlockFontColor = codeBlockFontColor
    self.codeBlockBackground = codeBlockBackground
    self.borderColor = borderColor
    self.blockquoteColor = blockquoteColor
    self.h1Color = h1Color
    self.h2Color = h2Color
    self.h3Color = h3Color
    self.h4Color = h4Color
    self.maxImageWidth = maxImageWidth
    self.maxImageHeight = maxImageHeight
    self.customStyle = customStyle
    self.imageBaseUrl = imageBaseUrl
  }

  /// Generates an attributed string from the given Markdown document
  open func generate(doc: Block) -> NSAttributedString? {
    if self.htmlRenderer == .direct {
      return self.directRenderer.render(doc: doc)
    }
    return self.generateAttributedString(self.htmlGenerator.generate(doc: doc))
  }

  /// Generates an attributed string from the given Markdown blocks
  open func generate(block: Block) -> NSAttributedString? {
    return self.generateAttributedString(self.htmlGenerator.generate(block: block, parent: .none))
  }

  /// Generates an attributed string from the given Markdown blocks
  open func generate(blocks: Blocks) -> NSAttributedString? {
    return self.generateAttributedString(self.htmlGenerator.generate(blocks: blocks, parent: .none))
  }
  
  // MARK: - ZMarkupParser (replacement for NSAttributedString HTML/WebKit)

  private lazy var zHTMLParser: ZHTMLParser = {
    return self.buildZHTMLParser()
  }()

  private func parseFontFamilyNames(_ cssFontFamily: String) -> [String] {
    return cssFontFamily
      .components(separatedBy: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
      .filter { !$0.isEmpty && $0 != "serif" && $0 != "sans-serif" && $0 != "monospace" }
  }

  private func buildZHTMLParser() -> ZHTMLParser {
    let baseFontNames = parseFontFamilyNames(self.fontFamily)
    let codeFontNames = parseFontFamilyNames(self.codeFontFamily)

    // Factor de conversión CSS px → iOS points, derivado empíricamente comparando
    // la salida de WebKit con ZMarkupParser (WebKit body 19pt para fontSize 21px → 0.905)
    let pxToPoints: CGFloat = 0.905
    let basePt = CGFloat(self.fontSize) * pxToPoints
    let codePt = CGFloat(self.codeFontSize) * pxToPoints
    let codeBlockPt = CGFloat(self.codeBlockFontSize) * pxToPoints
    let h1Pt = CGFloat(self.fontSize + 6) * pxToPoints
    let h2Pt = CGFloat(self.fontSize + 4) * pxToPoints
    let h3Pt = CGFloat(self.fontSize + 2) * pxToPoints
    let h4Pt = CGFloat(self.fontSize + 1) * pxToPoints

    let rootStyle = MarkupStyle(
      font: MarkupStyleFont(
        size: basePt,
        familyName: baseFontNames.isEmpty ? nil : .familyNames(baseFontNames)
      ),
      paragraphStyle: MarkupStyleParagraphStyle(
        paragraphSpacing: basePt * 0.7  // CSS: p { margin: 0.7em 0 }
      ),
      foregroundColor: MarkupStyleColor(string: self.fontColor)
    )

    var builder = ZHTMLParserBuilder.initWithDefault()
      .set(rootStyle: rootStyle)
      .set(policy: .respectMarkupStyleFromHTMLStyleAttribute)

    // Headings — sizes and spacing match CSS margins in em units
    builder = builder
      .set(H1_HTMLTagName(), withCustomStyle: MarkupStyle(
        font: MarkupStyleFont(size: h1Pt, weight: .style(.bold),
                               familyName: baseFontNames.isEmpty ? nil : .familyNames(baseFontNames)),
        paragraphStyle: MarkupStyleParagraphStyle(paragraphSpacing: h1Pt * 0.5, paragraphSpacingBefore: h1Pt * 0.7),
        foregroundColor: MarkupStyleColor(string: self.h1Color)
      ))
      .set(H2_HTMLTagName(), withCustomStyle: MarkupStyle(
        font: MarkupStyleFont(size: h2Pt, weight: .style(.bold),
                               familyName: baseFontNames.isEmpty ? nil : .familyNames(baseFontNames)),
        paragraphStyle: MarkupStyleParagraphStyle(paragraphSpacing: h2Pt * 0.4, paragraphSpacingBefore: h2Pt * 0.6),
        foregroundColor: MarkupStyleColor(string: self.h2Color)
      ))
      .set(H3_HTMLTagName(), withCustomStyle: MarkupStyle(
        font: MarkupStyleFont(size: h3Pt, weight: .style(.bold),
                               familyName: baseFontNames.isEmpty ? nil : .familyNames(baseFontNames)),
        paragraphStyle: MarkupStyleParagraphStyle(paragraphSpacing: h3Pt * 0.3, paragraphSpacingBefore: h3Pt * 0.5),
        foregroundColor: MarkupStyleColor(string: self.h3Color)
      ))
      .set(H4_HTMLTagName(), withCustomStyle: MarkupStyle(
        font: MarkupStyleFont(size: h4Pt, weight: .style(.bold),
                               familyName: baseFontNames.isEmpty ? nil : .familyNames(baseFontNames)),
        paragraphStyle: MarkupStyleParagraphStyle(paragraphSpacing: h4Pt * 0.2, paragraphSpacingBefore: h4Pt * 0.4),
        foregroundColor: MarkupStyleColor(string: self.h4Color)
      ))

    // Inline formatting
    builder = builder
      .set(STRONG_HTMLTagName(), withCustomStyle: MarkupStyle(
        font: MarkupStyleFont(weight: .style(.bold),
                               familyName: .familyNames(["Helvetica Neue Bold"]))
      ))
      .set(EM_HTMLTagName(), withCustomStyle: MarkupStyle(
        font: MarkupStyleFont(italic: true,
                               familyName: .familyNames(["Helvetica Neue Italic"]))
      ))
      .set(A_HTMLTagName(), withCustomStyle: MarkupStyle(
        foregroundColor: MarkupStyleColor(string: "#0000FF"),
        underlineStyle: .single
      ))

    // Code
    builder = builder
      .set(CODE_HTMLTagName(), withCustomStyle: MarkupStyle(
        font: MarkupStyleFont(size: codePt,
                               familyName: codeFontNames.isEmpty ? nil : .familyNames(codeFontNames)),
        foregroundColor: MarkupStyleColor(string: self.codeFontColor),
        backgroundColor: MarkupStyleColor(string: self.codeBlockBackground)
      ))
      .set(PRE_HTMLTagName(), withCustomStyle: MarkupStyle(
        font: MarkupStyleFont(size: codeBlockPt,
                               familyName: codeFontNames.isEmpty ? nil : .familyNames(codeFontNames)),
        foregroundColor: MarkupStyleColor(string: self.codeBlockFontColor),
        backgroundColor: MarkupStyleColor(string: self.codeBlockBackground)
      ))

    // Blockquote
    builder = builder
      .set(BLOCKQUOTE_HTMLTagName(), withCustomStyle: MarkupStyle(
        font: MarkupStyleFont(italic: true,
                               familyName: .familyNames(["Helvetica Neue Italic"])),
        paragraphStyle: MarkupStyleParagraphStyle(headIndent: 16, firstLineHeadIndent: 16),
        foregroundColor: MarkupStyleColor(string: self.blockquoteColor)
      ))

    // Lists — match WebKit: small headIndent, compact spacing
    builder = builder
      .set(UL_HTMLTagName(), withCustomStyle: MarkupStyle(
        paragraphStyle: MarkupStyleParagraphStyle(
          paragraphSpacing: basePt * 0.1,
          headIndent: 5,
          textListStyleType: .disc,
          textListHeadIndent: 5
        )
      ))
      .set(OL_HTMLTagName(), withCustomStyle: MarkupStyle(
        paragraphStyle: MarkupStyleParagraphStyle(
          paragraphSpacing: basePt * 0.1,
          headIndent: 5,
          textListStyleType: .decimal,
          textListHeadIndent: 5
        )
      ))
      .set(LI_HTMLTagName(), withCustomStyle: MarkupStyle(
        paragraphStyle: MarkupStyleParagraphStyle(
          paragraphSpacing: basePt * 0.1
        )
      ))

    // Table
    builder = builder
      .set(TABLE_HTMLTagName(), withCustomStyle: MarkupStyle(
        font: MarkupStyleFont(size: basePt)
      ))
      .set(TH_HTMLTagName(), withCustomStyle: MarkupStyle(
        font: MarkupStyleFont(weight: .style(.bold))
      ))

    // Definition lists (not natively supported — register as custom tags)
    builder = builder
      .add(ExtendTagName("dl"), withCustomStyle: nil)
      .add(ExtendTagName("dt"), withCustomStyle: MarkupStyle(font: MarkupStyleFont(weight: .style(.bold))))
      .add(ExtendTagName("dd"), withCustomStyle: MarkupStyle(
        paragraphStyle: MarkupStyleParagraphStyle(headIndent: 20, firstLineHeadIndent: 20)
      ))
      .add(ExtendTagName("thead"), withCustomStyle: nil)
      .add(ExtendTagName("tbody"), withCustomStyle: nil)

    // CSS class styles
    builder = builder
      .add(HTMLTagClassAttribute(className: "codebox") {
        MarkupStyle(backgroundColor: MarkupStyleColor(string: self.codeBlockBackground))
      })
      .add(HTMLTagClassAttribute(className: "quote") {
        MarkupStyle(foregroundColor: MarkupStyleColor(string: self.blockquoteColor))
      })
      .add(HTMLTagClassAttribute(className: "mtable") {
        MarkupStyle(font: MarkupStyleFont(size: basePt))
      })

    return builder.build()
  }

  private func generateAttributedString(_ htmlBody: String) -> NSAttributedString? {
    switch self.htmlRenderer {
    case .webKit:
      // WARNING: NSHTMLReader._loadUsingWebKit spins a nested run loop that can cause
      // reentrancy crashes in UITableView._updateVisibleCellsNow:.
      // Not safe to use during cell configuration in UITableView.
      if let httpData = self.generateHtml(htmlBody).data(using: .utf8) {
        if #available(iOS 18.0, *) {
          return try? NSAttributedString(data: httpData,
                                         options: [.documentType: NSAttributedString.DocumentType.html,
                                                   .characterEncoding: String.Encoding.utf8.rawValue,
                                                   .textKit1ListMarkerFormatDocumentOption: true],
                                         documentAttributes: nil)
        } else {
          return try? NSAttributedString(data: httpData,
                                         options: [.documentType: NSAttributedString.DocumentType.html,
                                                   .characterEncoding: String.Encoding.utf8.rawValue],
                                         documentAttributes: nil)
        }
      }
      return nil
    case .zMarkupParser:
      // Strip tags that WebKit interprets silently but ZMarkupParser renders as visible text.
      let stripped = htmlBody
        .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: "<head[^>]*>[\\s\\S]*?</head>", with: "", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: "</?html[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: "</?body[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
      return self.zHTMLParser.render(stripped)
    case .direct:
        return nil
    }
  }
  
  /// Custom fragment handler injected from the app layer for direct rendering.
  public var directCustomFragmentHandler: DirectAttributedStringRenderer.CustomFragmentHandler?

  private lazy var directRenderer: DirectAttributedStringRenderer = {
    var renderer = DirectAttributedStringRenderer(
      fontSize: self.fontSize,
      fontFamily: self.fontFamily.components(separatedBy: ",").first?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) ?? "Helvetica Neue",
      fontColor: self.fontColor,
      codeFontSize: self.codeFontSize,
      codeFontFamily: self.codeFontFamily.components(separatedBy: ",").first?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) ?? "Courier New",
      codeFontColor: self.codeFontColor,
      codeBlockFontSize: self.codeBlockFontSize,
      codeBlockFontColor: self.codeBlockFontColor,
      codeBlockBackground: self.codeBlockBackground,
      borderColor: self.borderColor,
      blockquoteColor: self.blockquoteColor,
      h1Color: self.h1Color,
      h2Color: self.h2Color,
      h3Color: self.h3Color,
      h4Color: self.h4Color
    )
    renderer.customFragmentHandler = self.directCustomFragmentHandler
    return renderer
  }()

  open var htmlGenerator: HtmlGenerator {
    return InternalHtmlGenerator(outer: self)
  }
  
  open func generateHtml(_ htmlBody: String) -> String {
    return "<html>\n\(self.htmlHead)\n\(self.htmlBody(htmlBody))\n</html>"
  }
  
  open var htmlHead: String {
    return "<head><meta charset=\"utf-8\"/><style type=\"text/css\">\n" +
           self.docStyle +
           "\n</style></head>\n"
  }

  open func htmlBody(_ body: String) -> String {
    return "<body>\n\(body)\n</body>"
  }

  open var docStyle: String {
    return "body             { \(self.bodyStyle) }\n" +
           "h1               { \(self.h1Style) }\n" +
           "h2               { \(self.h2Style) }\n" +
           "h3               { \(self.h3Style) }\n" +
           "h4               { \(self.h4Style) }\n" +
           "p                { \(self.pStyle) }\n" +
           "ul               { \(self.ulStyle) }\n" +
           "ol               { \(self.olStyle) }\n" +
           "li               { \(self.liStyle) }\n" +
           "table.blockquote { \(self.blockquoteStyle) }\n" +
           "table.mtable     { \(self.tableStyle) }\n" +
           "table.mtable thead th { \(self.tableHeaderStyle) }\n" +
           "pre              { \(self.preStyle) }\n" +
           "code             { \(self.codeStyle) }\n" +
           "pre code         { \(self.preCodeStyle) }\n" +
           "td.codebox       { \(self.codeBoxStyle) }\n" +
           "td.thematic      { \(self.thematicBreakStyle) }\n" +
           "td.quote         { \(self.quoteStyle) }\n" +
           "img              { \(self.imgStyle) }\n" +
           "dt {\n" +
           "  font-weight: bold;\n" +
           "  margin: 0.6em 0 0.4em 0;\n" +
           "}\n" +
           "dd {\n" +
           "  margin: 0.5em 0 1em 2em;\n" +
           "  padding: 0.5em 0 1em 2em;\n" +
           "}\n" +
           "\(self.customStyle)\n"
  }

  open var bodyStyle: String {
    return "font-size: \(self.fontSize)px;" +
           "font-family: \(self.fontFamily);" +
           "color: \(self.fontColor);"
  }

  open var h1Style: String {
    return "font-size: \(self.fontSize + 6)px;" +
           "color: \(self.h1Color);" +
           "margin: 0.7em 0 0.5em 0;"
  }

  open var h2Style: String {
    return "font-size: \(self.fontSize + 4)px;" +
           "color: \(self.h2Color);" +
           "margin: 0.6em 0 0.4em 0;"
  }

  open var h3Style: String {
    return "font-size: \(self.fontSize + 2)px;" +
           "color: \(self.h3Color);" +
           "margin: 0.5em 0 0.3em 0;"
  }

  open var h4Style: String {
    return "font-size: \(self.fontSize + 1)px;" +
           "color: \(self.h4Color);" +
           "margin: 0.5em 0 0.3em 0;"
  }

  open var pStyle: String {
    return "margin: 0.7em 0;"
  }

  open var ulStyle: String {
    return "margin: 0.7em 0;"
  }

  open var olStyle: String {
    return "margin: 0.7em 0;"
  }

  open var liStyle: String {
    return "margin-left: 0.25em;" +
           "margin-bottom: 0.1em;"
  }

  open var preStyle: String {
    return "background: \(self.codeBlockBackground);"
  }

  open var codeStyle: String {
    return "font-size: \(self.codeFontSize)px;" +
           "font-family: \(self.codeFontFamily);" +
           "color: \(self.codeFontColor);"
  }

  open var preCodeStyle: String {
    return "font-size: \(self.codeBlockFontSize)px;" +
           "font-family: \(self.codeFontFamily);" +
           "color: \(self.codeBlockFontColor);"
  }

  open var codeBoxStyle: String {
    return "background: \(self.codeBlockBackground);" +
           "width: 100%;" +
           "border: 1px solid \(self.borderColor);" +
           "padding: 0.5em;"
  }

  open var thematicBreakStyle: String {
    return "border-bottom: 1px solid \(self.borderColor);"
  }

  open var blockquoteStyle: String {
    return "width: 100%;" +
           "margin: 0.3em 0;" +
           "font-size: \(self.fontSize)px;"
  }
  
  open var quoteStyle: String {
    return "background: \(self.blockquoteColor);" +
           "width: 0.4em;"
  }
  
  open var imgStyle: String {
    if let maxWidth = self.maxImageWidth {
      if let maxHeight = self.maxImageHeight {
        return "max-width: \(maxWidth) !important;max-height: \(maxHeight) !important;" +
               "width: auto;height: auto;"
      } else {
        return "max-height: 100%;max-width: \(maxWidth) !important;width: auto;height: auto;"
      }
    } else if let maxHeight = self.maxImageHeight {
      return "max-width: 100%;max-height: \(maxHeight) !important;width: auto;height: auto;"
    } else {
      return ""
    }
  }
  
  open var tableStyle: String {
    return "border-collapse: collapse;" +
           "margin: 0.3em 0;" +
           "padding: 3px;" +
           "font-size: \(self.fontSize)px;"
  }
  
  open var tableHeaderStyle: String {
    return ""
  }
  
  open var tableCellPadding: Int {
    return 2
  }
}

#endif
