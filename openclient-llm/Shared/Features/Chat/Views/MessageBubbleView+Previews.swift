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
        message: ChatMessage(role: .assistant, content: "Would you like the story to continue?"),
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
        message: ChatMessage(role: .assistant, content: "Would you like the story to continue?"),
        hasTTS: true,
        isLastMessage: true,
        onSpeakTapped: {},
        onRegenerateTapped: {}
    )
    .padding(16)
    .frame(width: 320)
    .environment(\.dynamicTypeSize, .accessibility3)
}
