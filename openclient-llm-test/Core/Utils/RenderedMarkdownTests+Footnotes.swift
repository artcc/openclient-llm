//
//  RenderedMarkdownTests+Footnotes.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 13/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension RenderedMarkdownTests {
    func test_renderConcurrently_footnotes_numbersByFirstReferenceAndReusesNumbers() async throws {
        // Given
        let body = "First[^second], next[^first], repeat[^second]."
        let source = "[^first]: One.\n[^second]: Two.\n" + body

        // When
        let result = await MarkdownParser.renderConcurrently(source)
        let rendered = try XCTUnwrap(result)

        // Then
        XCTAssertEqual(String(rendered.attributedString(for: body).characters), "First¹, next², repeat¹.")
        XCTAssertEqual(rendered.footnotes, [
            MarkdownFootnote(number: 1, label: "second", content: "Two."),
            MarkdownFootnote(number: 2, label: "first", content: "One.")
        ])
    }

    func test_renderConcurrently_footnotes_preservesInlineFormatting() async throws {
        // Given
        let body = "**Fact[^source]** and *context*."
        let note = "See **details** and [source](https://example.com)."
        let source = body + "\n[^source]: " + note
        let expected = try AttributedString(
            markdown: "**Fact¹** and *context*.",
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )

        // When
        let result = await MarkdownParser.renderConcurrently(source)
        let rendered = try XCTUnwrap(result)

        // Then
        XCTAssertEqual(rendered.attributedString(for: body), expected)
        XCTAssertEqual(String(rendered.attributedString(for: note).characters), "See details and source.")
        XCTAssertTrue(rendered.attributedString(for: note).runs.contains {
            $0.link?.absoluteString == "https://example.com"
        })
    }

    func test_renderConcurrently_footnoteSyntaxInCodeEscapesAndLinks_preservesLiterals() async throws {
        // Given
        let literals = #"`[^note]` and ``code ` [^note]`` and \[^note] and [link](https://example.com/[^note])"#
        let body = literals + " and real[^note]."
        let expectedSource = literals + " and real¹."
        let expected = try AttributedString(
            markdown: expectedSource,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )

        // When
        let result = await MarkdownParser.renderConcurrently(body + "\n[^note]: Note.")
        let rendered = try XCTUnwrap(result)

        // Then
        XCTAssertEqual(rendered.attributedString(for: body), expected)
    }

    func test_renderConcurrently_unresolvedFootnote_keepsReferenceVisible() async throws {
        // Given
        let body = "Known[^known] and unknown[^missing]."

        // When
        let result = await MarkdownParser.renderConcurrently(body + "\n[^known]: Note.")
        let rendered = try XCTUnwrap(result)

        // Then
        XCTAssertEqual(String(rendered.attributedString(for: body).characters), "Known¹ and unknown[^missing].")
    }

    func test_renderConcurrently_tableAndHeadingReferences_resolvesBoth() async throws {
        // Given
        let source = "# Heading[^note]\nName | Value\n--- | ---\nItem[^note] | **42**\n[^note]: Context."

        // When
        let result = await MarkdownParser.renderConcurrently(source)
        let rendered = try XCTUnwrap(result)

        // Then
        XCTAssertEqual(String(rendered.attributedString(for: "Heading[^note]").characters), "Heading¹")
        XCTAssertEqual(String(rendered.attributedString(for: "Item[^note]").characters), "Item¹")
        XCTAssertEqual(String(rendered.attributedString(for: "**42**").characters), "42")
        XCTAssertEqual(rendered.footnotes.count, 1)
    }

    func test_renderConcurrently_duplicateDefinitions_usesFirstDefinition() async throws {
        // Given
        let source = "Fact[^note].\n[^note]: First.\n[^note]: Second."

        // When
        let result = await MarkdownParser.renderConcurrently(source)
        let rendered = try XCTUnwrap(result)

        // Then
        XCTAssertEqual(rendered.footnotes, [MarkdownFootnote(number: 1, label: "note", content: "First.")])
    }

    func test_renderConcurrently_unicodeAndEscapedBackslashes_preservesReferenceOffsets() async throws {
        // Given
        let body = #"á🙂[^a] **más[^b]** \\[^a] \[^a]"#
        let expected = try AttributedString(
            markdown: #"á🙂¹ **más²** \\¹ \[^a]"#,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )

        // When
        let result = await MarkdownParser.renderConcurrently(body + "\n[^a]: First.\n[^b]: Second.")
        let rendered = try XCTUnwrap(result)

        // Then
        XCTAssertEqual(rendered.attributedString(for: body), expected)
    }

    func test_renderConcurrently_referenceSyntaxInNestedLink_preservesLabelAndDestination() async throws {
        // Given
        let link = "[label[^note]](https://example.com/a(b)/[^note])"
        let body = link + " and reference[^note]."
        let expected = try AttributedString(
            markdown: link + " and reference¹.",
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )

        // When
        let result = await MarkdownParser.renderConcurrently(body + "\n[^note]: Note.")
        let rendered = try XCTUnwrap(result)

        // Then
        XCTAssertEqual(rendered.attributedString(for: body), expected)
    }
}
