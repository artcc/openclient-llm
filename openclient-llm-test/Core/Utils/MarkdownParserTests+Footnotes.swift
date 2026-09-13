//
//  MarkdownParserTests+Footnotes.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 13/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension MarkdownParserTests {
    func test_parse_footnoteDefinitions_extractsLabelsAndContent() {
        // Given
        let input = "Text[^1] and another[^source].\n[^1]: First note.\n[^source]: **Source** and `code`."

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        XCTAssertEqual(blocks, [
            .text("Text[^1] and another[^source]."),
            .footnote(label: "1", content: "First note."),
            .footnote(label: "source", content: "**Source** and `code`.")
        ])
    }

    func test_parse_multilineFootnote_preservesParagraphsAndFollowingText() {
        // Given
        let input = "[^note]: First line.\n    Second line.\n\n    Another paragraph.\nFollowing text."

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        XCTAssertEqual(blocks, [
            .footnote(label: "note", content: "First line.\nSecond line.\n\nAnother paragraph."),
            .text("Following text.")
        ])
    }

    func test_parse_footnoteWithHardLineBreak_includesContinuation() {
        // Given
        let input = "[^note]: First line.  \nSecond line.\nFollowing text."

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        XCTAssertEqual(blocks, [
            .footnote(label: "note", content: "First line.  \nSecond line."),
            .text("Following text.")
        ])
    }

    func test_parse_emptyFirstFootnoteLine_acceptsIndentedContent() {
        // Given
        let input = "[^note]:\n\tNote content."

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        XCTAssertEqual(blocks, [.footnote(label: "note", content: "Note content.")])
    }

    func test_parse_invalidOrEscapedFootnoteDefinitions_preservesLiteralText() {
        // Given
        let inputs = ["[^]: Note.", "[^two words]: Note.", "[^note]:", #"\[^note]: Literal."#]

        // When
        let results = inputs.map { MarkdownParser.parse($0) }

        // Then
        for (input, blocks) in zip(inputs, results) {
            XCTAssertEqual(blocks, [.text(input)])
        }
    }

    func test_parse_footnotesAndTablesInsideCode_preservesCodeVerbatim() {
        // Given
        let code = "[^note]: Literal.\nName | Age\n--- | ---\nAlice | 30\n\\*escaped\\*"

        // When
        let blocks = MarkdownParser.parse("```markdown\n" + code + "\n```")

        // Then
        XCTAssertEqual(blocks, [.codeBlock(code: code, language: "markdown")])
    }

    func test_parse_definitionInsideMultilineCodeSpan_preservesLiteralText() {
        // Given
        let source = "Example: ``literal ` syntax\n[^note]: Not a footnote.\n``"

        // When
        let blocks = MarkdownParser.parse(source)

        // Then
        XCTAssertEqual(blocks, [.text(source)])
    }
}
