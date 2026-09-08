//
//  ChatInputLayout.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 08/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

/// Wraps the action group above the entry row without replacing the text field or its focus.
struct ChatInputLayout: Layout {
    var minimumEntryWidth: CGFloat = 200

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(width: proposal.width, subviews: subviews)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(width: CGFloat?, subviews: Subviews) -> [CGRect] {
        guard subviews.count == 2 else { return [] }
        let actions = subviews[0].sizeThatFits(.unspecified)
        let availableWidth = width.flatMap { $0.isFinite ? $0 : nil } ?? (actions.width + 8 + minimumEntryWidth)
        let spacing: CGFloat = actions.width > 0 ? 8 : 0
        let wraps = actions.width + spacing + minimumEntryWidth > availableWidth
        let entryWidth = max(0, availableWidth - (wraps ? 0 : actions.width + spacing))
        let entry = subviews[1].sizeThatFits(ProposedViewSize(width: entryWidth, height: nil))

        if wraps {
            return [
                CGRect(origin: .zero, size: actions),
                CGRect(x: 0, y: actions.height + spacing, width: entryWidth, height: entry.height)
            ]
        }
        let height = max(actions.height, entry.height)
        return [
            CGRect(x: 0, y: (height - actions.height) / 2, width: actions.width, height: actions.height),
            CGRect(x: actions.width + spacing, y: 0, width: entryWidth, height: height)
        ]
    }
}
