//
//  ChatView+ModelSelector.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 03/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
import TipKit

// MARK: - Model Selector

extension ChatView {
    @ViewBuilder
    func modelSelector(using viewModel: ChatViewModel) -> some View {
        if case .loaded(let loadedState) = viewModel.state,
           !loadedState.availableModels.isEmpty {
            let availableModels = loadedState.availableModels
            let selectedModel = loadedState.selectedModel
            Menu {
                ForEach(availableModels) { model in
                    Button {
                        AppTips.modelSelector.invalidate(reason: .actionPerformed)
                        viewModel.send(.modelSelected(model))
                    } label: {
                        HStack {
                            Text(model.id)
                            if model == selectedModel {
                                Image(systemName: "checkmark")
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(model == selectedModel ? .isSelected : [])
                }
            } label: {
                HStack(spacing: 4) {
                    Text(
                        selectedModel?.id
                        ?? String(localized: "No Model")
                    )
                    .font(.poppins(.semiBold, size: 17, relativeTo: .headline))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 200)

#if os(iOS)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
#endif
                }
            }
            .popoverTip(availableModels.count > 1 ? AppTips.modelSelector : nil)
        }
    }
}
