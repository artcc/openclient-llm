//
//  RenderedMarkdownTests+Escapes.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 13/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension RenderedMarkdownTests {
    func test_renderConcurrently_escapedInlineMarkdown_preservesLiteralCharacters() async throws {
        // Given
        let source = #"\*literal\* \_text\_ \[brackets\] \`backticks\` \\path &amp; &lt;tag&gt;"#

        // When
        let result = await MarkdownParser.renderConcurrently(source)
        let rendered = try XCTUnwrap(result)
        let attributed = rendered.attributedString(for: source)

        // Then
        XCTAssertEqual(String(attributed.characters), #"*literal* _text_ [brackets] `backticks` \path & <tag>"#)
        XCTAssertFalse(attributed.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
        XCTAssertFalse(attributed.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    }

    func test_renderConcurrently_inlineCode_keepsEscapesAndEntitiesLiteral() async throws {
        // Given
        let source = #"`\*literal\* &amp; <b>code</b> [^note]`"#

        // When
        let result = await MarkdownParser.renderConcurrently(source + "\n[^note]: Note.")
        let rendered = try XCTUnwrap(result)

        // Then
        XCTAssertEqual(
            String(rendered.attributedString(for: source).characters),
            #"\*literal\* &amp; <b>code</b> [^note]"#
        )
        XCTAssertTrue(rendered.attributedString(for: source).runs.contains {
            $0.inlinePresentationIntent?.contains(.code) == true
        })
    }

    func test_renderConcurrently_escapedBlockMarkers_doesNotCreateBlocks() async throws {
        // Given
        let source = ##"""
        \# Heading
        \> Quote
        \- Item
        1\. Item
        \[^note]: Literal note syntax.
        """##

        // When
        let result = await MarkdownParser.renderConcurrently(source)
        let rendered = try XCTUnwrap(result)

        // Then
        XCTAssertEqual(rendered.blocks, [.text(source)])
        XCTAssertTrue(rendered.footnotes.isEmpty)
        XCTAssertEqual(String(rendered.attributedString(for: source).characters), """
        # Heading
        > Quote
        - Item
        1. Item
        [^note]: Literal note syntax.
        """)
    }

    func test_renderConcurrently_escapedPipeInTableCode_doesNotAddColumnOrBackslash() async throws {
        // Given
        let source = "Pattern | Description\n--- | ---\n`a\\|b` | A \\| B"

        // When
        let result = await MarkdownParser.renderConcurrently(source)
        let rendered = try XCTUnwrap(result)

        // Then
        XCTAssertEqual(rendered.blocks, [.table(
            headers: ["Pattern", "Description"],
            rows: [["`a|b`", "A | B"]]
        )])
        XCTAssertEqual(String(rendered.attributedString(for: "`a|b`").characters), "a|b")
        XCTAssertTrue(rendered.attributedString(for: "`a|b`").runs.contains {
            $0.inlinePresentationIntent?.contains(.code) == true
        })
    }

    func test_renderConcurrently_existingInlineSyntax_matchesFoundationWithFootnotesPresent() async throws {
        // Given
        let sources = [
            "**Bold**, *italic*, ~~removed~~, `code`, and [link](https://example.com)",
            #"\*literal\* and \\path and &amp; and &lt;tag&gt;"#,
            "<b>Bold</b><br><i>Other inline HTML</i>",
            #"Inline $x^2$ and \(\frac{a}{b}\) and $$E=mc^2$$"#
        ]

        for source in sources {
            let expected = try AttributedString(
                markdown: source,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )

            // When
            let result = await MarkdownParser.renderConcurrently(source + "\n[^note]: A note.")
            let rendered = try XCTUnwrap(result)

            // Then
            XCTAssertEqual(rendered.attributedString(for: source), expected)
        }
    }
}
