//
//  ChatInputBarView+Recording.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

extension ChatInputBarView {
    var startingRecordingBar: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Starting recording...").foregroundStyle(.secondary)
            Spacer()
            Button(action: onCancelRecording) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel Recording")
        }
        .frame(minHeight: 44)
    }
}
