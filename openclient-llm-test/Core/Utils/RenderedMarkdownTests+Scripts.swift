//
//  RenderedMarkdownTests+Scripts.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 13/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension RenderedMarkdownTests {
    func test_renderConcurrently_subAndSup_marksPositionsAndRemovesTags() async throws {
        // Given
        let source = "H<sub>2</sub>O and x<sup>n + 1</sup>."

        // When
        let result = await MarkdownParser.renderConcurrently(source)
        let rendered = try XCTUnwrap(result)
        let content = rendered.attributedString(for: source)

        // Then
        XCTAssertEqual(String(content.characters), "H2O and xn + 1.")
        let subscriptRange = try XCTUnwrap(content.range(of: "2"))
        let superscriptRange = try XCTUnwrap(content.range(of: "n + 1"))
        XCTAssertEqual(content[subscriptRange][MarkdownScriptAttribute.self], -1)
        XCTAssertEqual(content[superscriptRange][MarkdownScriptAttribute.self], 1)
        let plainRange = try XCTUnwrap(content.range(of: "O and x"))
        XCTAssertNil(content[plainRange][MarkdownScriptAttribute.self])
    }

    func test_renderConcurrently_scriptsWithFormattingAndLinks_preservesOtherAttributes() async throws {
        // Given
        let source = "**H<sub>2</sub>O** + [x<sup>*n*</sup>](https://example.com)."

        // When
        let result = await MarkdownParser.renderConcurrently(source)
        let rendered = try XCTUnwrap(result)
        let content = rendered.attributedString(for: source)

        // Then
        XCTAssertEqual(String(content.characters), "H2O + xn.")
        let subscriptRange = try XCTUnwrap(content.range(of: "2"))
        let superscriptRange = try XCTUnwrap(content.range(of: "n"))
        XCTAssertEqual(content[subscriptRange][MarkdownScriptAttribute.self], -1)
        XCTAssertEqual(content[superscriptRange][MarkdownScriptAttribute.self], 1)
        XCTAssertTrue(content[subscriptRange].inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        XCTAssertTrue(content[superscriptRange].inlinePresentationIntent?.contains(.emphasized) == true)
        XCTAssertEqual(content[superscriptRange].link?.absoluteString, "https://example.com")
    }

    func test_renderConcurrently_escapedEncodedAndCodeTags_keepsLiteralSyntax() async throws {
        // Given
        let sources = [
            #"\<sub>2\</sub> and \<sup>n\</sup>"#,
            "&lt;sub&gt;2&lt;/sub&gt; and &lt;sup&gt;n&lt;/sup&gt;",
            "`<sub>2</sub>` and ``<sup>n</sup>``",
            "Text <!-- <sup>comment</sup> --> and more text",
            "Text <span title='<sup>'>value</span></sup>",
            "[link](https://example.com/%3Csup%3En%3C/sup%3E)"
        ]

        for source in sources {
            let expected = try AttributedString(
                markdown: source,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )

            // When
            let result = await MarkdownParser.renderConcurrently(source)
            let rendered = try XCTUnwrap(result)

            // Then
            XCTAssertEqual(rendered.attributedString(for: source), expected)
        }
    }

    func test_renderConcurrently_unmatchedAndCrossedTags_keepsExistingRendering() async throws {
        // Given
        let sources = [
            "x<sup>2",
            "x2</sup>",
            "x<sub>2</sup>",
            "x<sup><sub>2</sup></sub>",
            "x<sup class=\"custom\">2</sup>"
        ]

        for source in sources {
            let expected = try AttributedString(
                markdown: source,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )

            // When
            let result = await MarkdownParser.renderConcurrently(source)
            let rendered = try XCTUnwrap(result)

            // Then
            XCTAssertEqual(rendered.attributedString(for: source), expected)
        }
    }

    func test_renderConcurrently_nestedAndUppercaseTags_appliesInnermostPosition() async throws {
        // Given
        let source = "x<SUP>a<SUB>b</SUB>c</SUP> and H<SUB>2</SUB>O"

        // When
        let result = await MarkdownParser.renderConcurrently(source)
        let rendered = try XCTUnwrap(result)
        let content = rendered.attributedString(for: source)

        // Then
        XCTAssertEqual(String(content.characters), "xabc and H2O")
        for text in ["a", "c"] {
            let range = try XCTUnwrap(content.range(of: text))
            XCTAssertEqual(content[range][MarkdownScriptAttribute.self], 1)
        }
        let nestedRange = try XCTUnwrap(content.range(of: "b"))
        XCTAssertEqual(content[nestedRange][MarkdownScriptAttribute.self], -1)
    }

    func test_renderConcurrently_scriptsAcrossBlockTypes_usesSharedInlineRendering() async throws {
        // Given
        let source = """
        # Heading x<sup>2</sup>
        > Quote H<sub>2</sub>O
        - List x<sup>n</sup>
        1. Numbered H<sub>2</sub>O
        - [x] Task x<sup>3</sup>

        Name | Value
        --- | ---
        Water | H<sub>2</sub>O

        Note[^chemistry].
        [^chemistry]: Water is H<sub>2</sub>O.
        """

        // When
        let result = await MarkdownParser.renderConcurrently(source)
        let rendered = try XCTUnwrap(result)

        // Then
        let expectations: [(String, Int)] = [
            ("Heading x<sup>2</sup>", 1), ("Quote H<sub>2</sub>O", -1),
            ("List x<sup>n</sup>", 1), ("Numbered H<sub>2</sub>O", -1),
            ("Task x<sup>3</sup>", 1), ("H<sub>2</sub>O", -1),
            ("Water is H<sub>2</sub>O.", -1)
        ]
        for (text, position) in expectations {
            let content = try XCTUnwrap(rendered.inlineContent[text])
            XCTAssertTrue(content.runs.contains { $0[MarkdownScriptAttribute.self] == position }, text)
        }
        XCTAssertEqual(rendered.footnotes.count, 1)
    }

    func test_renderConcurrently_fencedHTML_remainsCode() async throws {
        // Given
        let code = "H<sub>2</sub>O and x<sup>2</sup>"

        // When
        let result = await MarkdownParser.renderConcurrently("```html\n" + code + "\n```")
        let rendered = try XCTUnwrap(result)

        // Then
        XCTAssertEqual(rendered.blocks, [.codeBlock(code: code, language: "html")])
        XCTAssertTrue(rendered.inlineContent.isEmpty)
    }

    func test_renderConcurrently_scriptLinkWithOuterBold_preservesNestedFormattingAndURL() async throws {
        // Given
        let source = "**[x<sup>*n*</sup>](https://example.com/a(b) \"Example\")**"

        // When
        let result = await MarkdownParser.renderConcurrently(source)
        let rendered = try XCTUnwrap(result)
        let content = rendered.attributedString(for: source)

        // Then
        XCTAssertEqual(String(content.characters), "xn")
        let range = try XCTUnwrap(content.range(of: "n"))
        XCTAssertEqual(content[range][MarkdownScriptAttribute.self], 1)
        XCTAssertEqual(content[range].link?.absoluteString, "https://example.com/a(b)")
        XCTAssertTrue(content[range].inlinePresentationIntent?.contains(.emphasized) == true)
        XCTAssertTrue(content[range].inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
    }

    func test_renderConcurrently_identicalURLsWithEscapedAndRealTags_formatsOnlyRealTags() async throws {
        // Given
        let literalLink = #"[x\<sup>*n*\</sup>](https://example.com)"#
        let scriptLink = "[x<sup>*n*</sup>](https://example.com)"
        let literal = try AttributedString(
            markdown: literalLink,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        let cases = [
            (literalLink + " + " + scriptLink, String(literal.characters) + " + xn"),
            (scriptLink + " + " + literalLink, "xn + " + String(literal.characters))
        ]

        for (source, expected) in cases {
            // When
            let result = await MarkdownParser.renderConcurrently(source)
            let rendered = try XCTUnwrap(result)
            let content = rendered.attributedString(for: source)

            // Then
            XCTAssertEqual(String(content.characters), expected)
            let literalRange = try XCTUnwrap(content.range(of: String(literal.characters)))
            XCTAssertFalse(content[literalRange].runs.contains { $0[MarkdownScriptAttribute.self] != nil })
            let scriptRange = try XCTUnwrap(content.range(of: "xn"))
            XCTAssertTrue(content[scriptRange].runs.contains { $0[MarkdownScriptAttribute.self] == 1 })
        }
    }

    func test_renderConcurrently_codeLinkBesideScriptLink_keepsCodeTagsLiteral() async throws {
        // Given
        let codeLink = "[`<sup>n</sup>`](https://example.com)"
        let source = codeLink + " + [H<sub>2</sub>O](https://example.com)"
        let code = try AttributedString(
            markdown: codeLink,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )

        // When
        let result = await MarkdownParser.renderConcurrently(source)
        let rendered = try XCTUnwrap(result)
        let content = rendered.attributedString(for: source)

        // Then
        XCTAssertEqual(String(content.characters), String(code.characters) + " + H2O")
        let codeRange = try XCTUnwrap(content.range(of: String(code.characters)))
        XCTAssertEqual(AttributedString(content[codeRange]), code)
        let subscriptRange = try XCTUnwrap(content.range(of: "2"))
        XCTAssertEqual(content[subscriptRange][MarkdownScriptAttribute.self], -1)
    }
}
