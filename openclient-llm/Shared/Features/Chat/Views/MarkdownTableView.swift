//
//  MarkdownTableView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 29/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct MarkdownTableView: View {
    // MARK: - Properties

    let headers: [String]
    let rows: [[String]]
    let inlineContent: [String: AttributedString]

    init(
        headers: [String],
        rows: [[String]],
        inlineContent: [String: AttributedString]
    ) {
        self.headers = headers
        self.rows = rows
        self.inlineContent = inlineContent
    }

    // MARK: - View

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                headerRow
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    dataRow(row, isAlternate: index % 2 != 0)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Private

private extension MarkdownTableView {
    var headerRow: some View {
        GridRow {
            ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                cellView(inlineContent[header] ?? AttributedString(header), isBold: true)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .trailing) {
                        if index < headers.count - 1 {
                            verticalDivider
                        }
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.appAccent.opacity(0.3))
                            .frame(height: 1)
                    }
            }
        }
    }

    func dataRow(_ cells: [String], isAlternate: Bool) -> some View {
        GridRow {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                cellView(inlineContent[cell] ?? AttributedString(cell), isBold: false)
                    .background(isAlternate ? Color.primary.opacity(0.03) : Color.clear)
                    .overlay(alignment: .trailing) {
                        if index < cells.count - 1 {
                            verticalDivider
                        }
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 1)
                    }
            }
        }
    }

    func cellView(_ content: AttributedString, isBold: Bool) -> some View {
        Text(content)
            .font(isBold ? .subheadline.weight(.semibold) : .subheadline)
            .foregroundStyle(Color.primary)
            .textSelection(.enabled)
            .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .gridCellUnsizedAxes(.vertical)
    }

    var verticalDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1)
    }

}

#Preview {
    let firstHeaders = ["Name", "Type", "Description"]
    let firstRows = [
        ["id", "Int", "Unique identifier"],
        ["name", "String", "User's full name"],
        ["email", "String", "Contact email"]
    ]
    let secondHeaders = ["Feature", "Status"]
    let secondRows = [
        ["Markdown", "Done"],
        ["Tables", "Done"],
        ["Syntax Highlighting", "Pending"]
    ]

    VStack(spacing: 16) {
        MarkdownTableView(
            headers: firstHeaders,
            rows: firstRows,
            inlineContent: [:]
        )

        MarkdownTableView(
            headers: secondHeaders,
            rows: secondRows,
            inlineContent: [:]
        )
    }
    .padding()
}

#Preview("Uneven Rows and Long Content") {
    MarkdownTableView(
        headers: ["Field", "Description", "Value"],
        rows: [
            ["id", "Unique identifier", "42"],
            ["notificationPreferences", "Delivery settings for all conversation updates", "Enabled"],
            ["notes", "First line\nSecond line", ""],
            ["Partial row"],
            ["Extra cells", "Preserved", "Visible", "Additional value"]
        ],
        inlineContent: [:]
    )
    .padding()
    .frame(width: 340)
}
