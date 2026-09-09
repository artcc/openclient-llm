//
//  TaskListView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 29/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct TaskListView: View {
    // MARK: - Properties

    let items: [MarkdownTaskItem]
    let inlineContent: [String: AttributedString]

    init(items: [MarkdownTaskItem], inlineContent: [String: AttributedString]) {
        self.items = items
        self.inlineContent = inlineContent
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                taskItemRow(item)
            }
        }
    }
}

// MARK: - Private

private extension TaskListView {
    func taskItemRow(_ item: MarkdownTaskItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                .foregroundStyle(item.isChecked ? Color.appAccent : Color.primary.opacity(0.4))
                .font(.body)
                .frame(width: 16, alignment: .center)
                .padding(.leading, CGFloat(item.depth) * 16)
                .accessibilityHidden(true)

            Text(inlineContent[item.content] ?? AttributedString(item.content))
                .font(.body)
                .foregroundStyle(item.isChecked ? Color.primary.opacity(0.6) : Color.primary)
                .strikethrough(item.isChecked)
                .accessibilityValue(item.isChecked
                    ? String(localized: "Completed")
                    : String(localized: "Not completed"))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}

#Preview {
    let basicItems = [
        MarkdownTaskItem(isChecked: false, content: "Pending task", depth: 0),
        MarkdownTaskItem(isChecked: true, content: "Completed task", depth: 0),
        MarkdownTaskItem(isChecked: false, content: "Another pending", depth: 0)
    ]
    let nestedItems = [
        MarkdownTaskItem(isChecked: false, content: "Parent task", depth: 0),
        MarkdownTaskItem(isChecked: true, content: "Done subtask with code", depth: 1),
        MarkdownTaskItem(isChecked: false, content: "Pending subtask", depth: 1)
    ]

    VStack(alignment: .leading, spacing: 16) {
        TaskListView(
            items: basicItems,
            inlineContent: [:]
        )
        TaskListView(
            items: nestedItems,
            inlineContent: [:]
        )
    }
    .padding()
}
