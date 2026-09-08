//
//  ChatInputBarView+Previews.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 08/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

private struct ChatInputBarPreview: View {
    @State private var showActions = true

    var body: some View {
        ChatInputBarView(
            showImagePicker: .constant(false),
            showDocumentPicker: .constant(false),
            showCameraPicker: .constant(false),
            state: ChatInputBarState(loadedState: .init(
                inputText: "Help me review this layout.",
                selectedModel: LLMModel(id: "Preview", capabilities: [.functionCalling])
            )),
            onSend: { _ in },
            onStopStreaming: {},
            onStartRecording: {},
            onStopRecording: {},
            onCancelRecording: {},
            onWebSearchToggled: {},
            onMCPButtonTapped: {},
            showActions: $showActions,
            showImageFilePicker: .constant(false)
        )
        .padding(.vertical, 16)
    }
}

#Preview("Compact composer") {
    ChatInputBarPreview()
        .frame(width: 320)
}

#Preview("Wide composer") {
    ChatInputBarPreview()
        .frame(width: 800)
}

#Preview("Large text composer") {
    ChatInputBarPreview()
        .frame(width: 390)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Right-to-left composer") {
    ChatInputBarPreview()
        .frame(width: 390)
        .environment(\.layoutDirection, .rightToLeft)
}
