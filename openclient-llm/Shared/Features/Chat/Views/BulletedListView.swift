//
//  BulletedListView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 29/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct BulletedListView: View {
    // MARK: - Properties

    let items: [MarkdownListItem]
    let inlineContent: [String: AttributedString]

    init(items: [MarkdownListItem], inlineContent: [String: AttributedString]) {
        self.items = items
        self.inlineContent = inlineContent
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                bulletItemRow(item)
            }
        }
    }
}

// MARK: - Private

private extension BulletedListView {
    func bulletItemRow(_ item: MarkdownListItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(bullet(for: item.depth))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.appAccent)
                .frame(width: 16, alignment: .center)
                .padding(.leading, CGFloat(item.depth) * 16)

            MarkdownInlineText(inlineContent[item.content] ?? AttributedString(item.content))
                .font(.body)
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func bullet(for depth: Int) -> String {
        let bullets = ["•", "◦", "▪", "▹", "▸"]
        let index = depth % bullets.count
        return bullets[index]
    }

}

#Preview {
    let basicItems = [
        MarkdownListItem(content: "First item", depth: 0),
        MarkdownListItem(content: "Second item", depth: 0),
        MarkdownListItem(content: "Third item", depth: 0)
    ]
    let nestedItems = [
        MarkdownListItem(content: "Parent item", depth: 0),
        MarkdownListItem(content: "Nested child", depth: 1),
        MarkdownListItem(content: "Another nested child", depth: 1),
        MarkdownListItem(content: "Back to parent", depth: 0),
        MarkdownListItem(content: "Deeply nested with code", depth: 2)
    ]

    VStack(alignment: .leading, spacing: 16) {
        BulletedListView(
            items: basicItems,
            inlineContent: [:]
        )
        BulletedListView(
            items: nestedItems,
            inlineContent: [:]
        )
    }
    .padding()
}
