//
//  MessageBubbleView+Status.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

extension MessageBubbleView {
    var thinkingIndicator: some View {
        Text(String(localized: "Thinking..."))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    var interruptionNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(String(localized: "Response interrupted"), systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            if isLastMessage, let onRegenerateTapped {
                Button(action: onRegenerateTapped) {
                    Label(String(localized: "Retry Response"), systemImage: "arrow.clockwise")
                        .font(.caption)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appAccent)
                .disabled(!isInterruptedRetryEnabled)
                .accessibilityHint(String(localized: "Starts a new response for this message."))
            }
        }
    }
}
