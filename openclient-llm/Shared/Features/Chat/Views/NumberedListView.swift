//
//  NumberedListView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 29/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct NumberedListView: View {
    // MARK: - Properties

    let items: [MarkdownOrderedListItem]
    let inlineContent: [String: AttributedString]

    init(items: [MarkdownOrderedListItem], inlineContent: [String: AttributedString]) {
        self.items = items
        self.inlineContent = inlineContent
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                numberedItemRow(item)
            }
        }
    }
}

// MARK: - Private

private extension NumberedListView {
    func numberedItemRow(_ item: MarkdownOrderedListItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(item.number).")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.appAccent)
                .frame(minWidth: 24, alignment: .trailing)
                .padding(.leading, CGFloat(item.depth) * 16)

            MarkdownInlineText(inlineContent[item.content] ?? AttributedString(item.content))
                .font(.body)
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}

#Preview {
    let basicItems = [
        MarkdownOrderedListItem(number: 1, content: "First step", depth: 0),
        MarkdownOrderedListItem(number: 2, content: "Second step", depth: 0),
        MarkdownOrderedListItem(number: 3, content: "Third step", depth: 0)
    ]
    let nestedItems = [
        MarkdownOrderedListItem(number: 1, content: "Main task", depth: 0),
        MarkdownOrderedListItem(number: 1, content: "Subtask A", depth: 1),
        MarkdownOrderedListItem(number: 2, content: "Subtask B", depth: 1),
        MarkdownOrderedListItem(number: 2, content: "Another main task", depth: 0)
    ]

    VStack(alignment: .leading, spacing: 16) {
        NumberedListView(
            items: basicItems,
            inlineContent: [:]
        )
        NumberedListView(
            items: nestedItems,
            inlineContent: [:]
        )
    }
    .padding()
}
