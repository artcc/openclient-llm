//
//  ChatView+Attachments.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

// MARK: - Error Banner & Attachment Preview

extension ChatView {
    // MARK: - Error Banner

    @ViewBuilder
    func errorBanner(_ errorMessage: String?) -> some View {
        if let errorMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(12)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Attachment Preview

    @ViewBuilder
    func attachmentPreview(
        _ attachments: [ChatMessage.Attachment],
        send: @escaping (ChatViewModel.Event) -> Void
    ) -> some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(attachments) { attachment in
                        attachmentThumbnail(attachment, onRemove: { send(.attachmentRemoved(attachment.id)) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    func attachmentThumbnail(_ attachment: ChatMessage.Attachment, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.type == .image ? "photo" : "doc.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(attachment.fileName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 180)
                .foregroundStyle(.primary)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
#if os(iOS)
                    .frame(width: 44, height: 44)
#else
                    .frame(width: 28, height: 28)
#endif
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove attachment \(attachment.fileName)"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .glassEffect(.regular, in: .capsule)
    }
}
