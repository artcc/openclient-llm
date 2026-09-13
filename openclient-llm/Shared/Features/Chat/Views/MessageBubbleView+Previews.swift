//
//  MessageBubbleView+Previews.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

#Preview("User message") {
    MessageBubbleView(
        message: ChatMessage(role: .user, content: "Hello, how are you?")
    )
    .padding()
}

// swiftlint:disable line_length
#Preview("Assistant message") {
    MessageBubbleView(
        message: ChatMessage(
            role: .assistant,
            content: "I'm doing great! **How can I help you** today?\n\nHere's a list:\n- Item one\n- Item two\n- Item three"
        )
    )
    .padding()
}

#Preview("Code block") {
    MessageBubbleView(
        message: ChatMessage(
            role: .assistant,
            content: "Sure! Here's how to do it in Swift:\n\n```swift\nfunc greet(name: String) -> String {\n    return \"Hello, \\(name)!\"\n}\n```\n\nJust call `greet(name: \"World\")` and you're done."
        )
    )
    .padding()
}
// swiftlint:enable line_length

#Preview("Streaming message") {
    MessageBubbleView(
        message: ChatMessage(
            role: .assistant,
            content: "Let me think about that..."
        ),
        isStreaming: true
    )
    .padding()
}

#Preview("Multiple attachments, compact") {
    MessageBubbleView(
        message: ChatMessage(
            role: .user,
            content: "Please compare these documents.",
            attachments: [
                .init(type: .pdf, fileName: "First document.pdf", mimeType: "application/pdf", fileRelativePath: ""),
                .init(type: .pdf, fileName: "Second document.pdf", mimeType: "application/pdf", fileRelativePath: ""),
                .init(type: .pdf, fileName: "Notes.pdf", mimeType: "application/pdf", fileRelativePath: "")
            ]
        )
    )
    .padding(16)
    .frame(width: 320)
}

#Preview("Assistant actions, compact") {
    MessageBubbleView(
        message: ChatMessage(
            role: .assistant,
            content: "Would you like the story to continue?",
            tokenUsage: TokenUsage(totalTokens: 6573)
        ),
        hasTTS: true,
        isLastMessage: true,
        onSpeakTapped: {},
        onRegenerateTapped: {}
    )
    .padding(16)
    .frame(width: 390)
}

#Preview("Attachment without text") {
    MessageBubbleView(
        message: ChatMessage(
            role: .user,
            content: "",
            attachments: [
                .init(type: .pdf, fileName: "Document.pdf", mimeType: "application/pdf", fileRelativePath: "")
            ]
        )
    )
    .padding(16)
    .frame(width: 390)
}

#Preview("Assistant actions, large text") {
    MessageBubbleView(
        message: ChatMessage(
            role: .assistant,
            content: "Would you like the story to continue?",
            tokenUsage: TokenUsage(totalTokens: 6573)
        ),
        hasTTS: true,
        isLastMessage: true,
        onSpeakTapped: {},
        onRegenerateTapped: {}
    )
    .padding(16)
    .frame(width: 320)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Conversation spacing") {
    ScrollView {
        VStack(spacing: 16) {
            MessageBubbleView(
                message: ChatMessage(
                    role: .assistant,
                    content: "Would you like me to compare these images?",
                    tokenUsage: TokenUsage(totalTokens: 6655)
                ),
                hasTTS: true,
                onSpeakTapped: {}
            )
            MessageBubbleView(message: ChatMessage(role: .user, content: "Hello"))
            MessageBubbleView(
                message: ChatMessage(
                    role: .assistant,
                    content: "Hello! 😊\n\nHow can I help you today?",
                    tokenUsage: TokenUsage(totalTokens: 6573)
                ),
                hasTTS: true,
                isLastMessage: true,
                onSpeakTapped: {},
                onRegenerateTapped: {}
            )
        }
        .padding(16)
    }
    .frame(width: 390)
}

#Preview("Table without outer pipes and footnotes") {
    MessageBubbleView(
        message: ChatMessage(
            role: .assistant,
            content: #"""
            ## Comparison[^context]

            Name | Value | Pattern
            --- | ---: | ---
            **First** | 42[^source] | `a\|b`
            Second | 18 | c\|d

            The same source is used again[^source].

            [^source]: See the **original** [source](https://example.com).
            [^context]: These values are examples.
                This note continues on another line.
            """#
        )
    )
    .padding(16)
    .frame(width: 390)
}

#Preview("Sub and sup in Markdown") {
    ScrollView {
        MessageBubbleView(
            message: ChatMessage(
                role: .assistant,
                content: #"""
                ## H<sub>2</sub>O and x<sup>n + 1</sup>

                **Water: H<sub>2</sub>O.** Powers: x<sup>2</sup> + y<sup>2</sup>.

                A formatted link: [x<sup>*n*</sup>](https://example.com).

                - CO<sub>2</sub> and a<sub>index</sub>
                - [x] Check x<sup>n + 1</sup>

                > A quote containing H<sub>2</sub>O.

                Name | Value
                --- | ---
                Water | H<sub>2</sub>O
                Power | x<sup>n + 1</sup>

                Literal: `<sup>2</sup>` and \<sub>2\</sub>.
                A reference[^note].

                [^note]: Compare H<sub>2</sub>O with CO<sub>2</sub>.
                """#
            )
        )
        .padding(16)
    }
    .frame(width: 390)
}
