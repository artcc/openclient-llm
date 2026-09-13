//
//  MarkdownParserTests+Media.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 29/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

// MARK: - Images

extension MarkdownParserTests {
    func test_parse_imageLine_basic_returnsImage() {
        // Given
        let input = "![Diagram](https://example.com/diagram.png)"

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        guard case .image(let alt, let url) = blocks[0] else {
            XCTFail("Expected .image"); return
        }
        XCTAssertEqual(alt, "Diagram")
        XCTAssertEqual(url, "https://example.com/diagram.png")
    }

    func test_parse_imageLine_emptyAlt_returnsImage() {
        // Given
        let input = "![](https://example.com/photo.jpg)"

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        guard case .image(let alt, let url) = blocks[0] else {
            XCTFail("Expected .image"); return
        }
        XCTAssertEqual(alt, "")
        XCTAssertEqual(url, "https://example.com/photo.jpg")
    }

    func test_parse_imageLine_withSurroundingText_separatesCorrectly() {
        // Given
        let input = "Intro\n![Photo](https://example.com/pic.jpg)\nOutro"

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        XCTAssertEqual(blocks.count, 3)
        guard case .text(let intro) = blocks[0] else {
            XCTFail("Expected .text first"); return
        }
        guard case .image(let alt, _) = blocks[1] else {
            XCTFail("Expected .image second"); return
        }
        guard case .text(let outro) = blocks[2] else {
            XCTFail("Expected .text third"); return
        }
        XCTAssertEqual(intro, "Intro")
        XCTAssertEqual(alt, "Photo")
        XCTAssertEqual(outro, "Outro")
    }

    func test_parse_imageLine_trailingText_notTreatedAsImage() {
        // Given
        let input = "![alt](url) trailing text"

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        guard case .text = blocks[0] else {
            XCTFail("Expected .text"); return
        }
    }

    func test_parse_imageLine_missingParenthesis_notTreatedAsImage() {
        // Given
        let input = "![alt] just alt text"

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        guard case .text = blocks[0] else {
            XCTFail("Expected .text"); return
        }
    }

    func test_parse_imageLine_missingBracket_notTreatedAsImage() {
        // Given
        let input = "![alt url)"

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        guard case .text = blocks[0] else {
            XCTFail("Expected .text"); return
        }
    }
}

// MARK: - Tables

extension MarkdownParserTests {
    func test_parse_simpleTable_returnsTable() {
        // Given
        let input = "| Name | Age |\n| --- | --- |\n| Alice | 30 |\n| Bob | 25 |"

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let headers, let rows) = blocks[0] else {
            XCTFail("Expected .table"); return
        }
        XCTAssertEqual(headers, ["Name", "Age"])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], ["Alice", "30"])
        XCTAssertEqual(rows[1], ["Bob", "25"])
    }

    func test_parse_tableThreeColumns_parsesCorrectly() {
        // Given
        let input = "| ID | Name | Active |\n| -- | ---- | ------ |\n| 1 | Foo | Yes |"

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        guard case .table(let headers, let rows) = blocks[0] else {
            XCTFail("Expected .table"); return
        }
        XCTAssertEqual(headers.count, 3)
        XCTAssertEqual(rows[0].count, 3)
        XCTAssertEqual(headers, ["ID", "Name", "Active"])
    }

    func test_parse_tableWithAlignmentMarkers_parsesCorrectly() {
        // Given
        let input = "| Left | Right | Center |\n| :--- | ---: | :---: |\n| A | B | C |"

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        guard case .table(let headers, let rows) = blocks[0] else {
            XCTFail("Expected .table"); return
        }
        XCTAssertEqual(headers, ["Left", "Right", "Center"])
        XCTAssertEqual(rows[0], ["A", "B", "C"])
    }

    func test_parse_tableWithSurroundingText_separatesCorrectly() {
        // Given
        let input = "Intro\n| K | V |\n| - | - |\n| A | 1 |\nOutro"

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        XCTAssertEqual(blocks.count, 3)
        guard case .text(let intro) = blocks[0] else {
            XCTFail("Expected .text first"); return
        }
        guard case .table = blocks[1] else {
            XCTFail("Expected .table second"); return
        }
        guard case .text(let outro) = blocks[2] else {
            XCTFail("Expected .text third"); return
        }
        XCTAssertEqual(intro, "Intro")
        XCTAssertEqual(outro, "Outro")
    }

    func test_parse_lineWithPipesButNoSeparator_notTreatedAsTable() {
        // Given
        let input = "This | is not | a table"

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        guard case .text = blocks[0] else {
            XCTFail("Expected .text"); return
        }
    }

    func test_parse_tableWithOptionalOuterPipes_returnsSameCells() {
        // Given
        let inputs = [
            "Name | Age\n--- | ---\nAlice | 30",
            "| Name | Age |\n--- | ---\nAlice | 30",
            "Name | Age\n| --- | --- |\n| Alice | 30 |",
            "Name | Age |\n:--- | ---:\n| Alice | 30"
        ]

        // When
        let results = inputs.map { MarkdownParser.parse($0) }

        // Then
        for blocks in results {
            XCTAssertEqual(blocks, [.table(headers: ["Name", "Age"], rows: [["Alice", "30"]])])
        }
    }

    func test_parse_tableWithEscapedPipes_preservesLiteralPipesAndEmptyCells() {
        // Given
        let input = #"""
        Pattern | Value | Empty
        --- | --- | ---
        a\|b | `x\|y` | |
        \| | trailing\| | |
        """#

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        XCTAssertEqual(blocks, [.table(
            headers: ["Pattern", "Value", "Empty"],
            rows: [["a|b", "`x|y`", ""], ["|", "trailing|", ""]]
        )])
    }

    func test_parse_tableWithEscapedBackslash_keepsFollowingPipeAsSeparator() {
        // Given
        let input = #"""
        Path | Value
        --- | ---
        C:\\| 42
        """#

        // When
        let blocks = MarkdownParser.parse(input)

        // Then
        XCTAssertEqual(blocks, [.table(headers: ["Path", "Value"], rows: [[#"C:\\"#, "42"]])])
    }

    func test_parse_invalidTableSeparators_preservesText() {
        // Given
        let inputs = [
            "Name | Age\n--- | :\nAlice | 30",
            "Name | Age\n--- | --:--\nAlice | 30",
            "Name | Age\n--- | --- | ---\nAlice | 30",
            "Name \\| Age\n--- | ---\nAlice | 30"
        ]

        // When
        let results = inputs.map { MarkdownParser.parse($0) }

        // Then
        for (input, blocks) in zip(inputs, results) {
            XCTAssertEqual(blocks, [.text(input)])
        }
    }

    func test_parse_tableFollowedByBlocksContainingPipes_doesNotConsumeNextBlock() {
        // Given
        let table = "Name | Age\n--- | ---\nAlice | 30\n"
        let suffixes: [(String, MessageBlock)] = [
            ("# Heading | Details", .heading(text: "Heading | Details", level: 1)),
            ("> Quote | Details", .blockquote("Quote | Details")),
            ("- Item | Details", .unorderedList(items: [.init(content: "Item | Details", depth: 0)])),
            ("```\na | b\n```", .codeBlock(code: "a | b", language: nil)),
            ("[^source]: A | B", .footnote(label: "source", content: "A | B"))
        ]

        // When
        let results = suffixes.map { MarkdownParser.parse(table + $0.0) }

        // Then
        for (suffix, blocks) in zip(suffixes, results) {
            XCTAssertEqual(blocks, [.table(headers: ["Name", "Age"], rows: [["Alice", "30"]]), suffix.1])
        }
    }
}
