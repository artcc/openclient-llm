//
//  ImageAndVisionSection.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct ImageAndVisionSection: View {
    // MARK: - Properties

    let loadedState: ModelsViewModel.LoadedState
    let sendEvent: (ModelsViewModel.Event) -> Void

    // MARK: - View

    var body: some View {
        Section {
            modelPicker(
                "Vision",
                models: loadedState.visionModels,
                selection: Binding(
                    get: { loadedState.selectedVisionModelId },
                    set: { sendEvent(.visionModelSelected($0)) }
                ),
                isUnavailable: loadedState.isSelectedVisionModelUnavailable
            )
            if loadedState.isSelectedVisionSpecialistUnsupported {
                Text("This model advertises vision, but its mode does not support automatic vision requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            modelPicker(
                "Image Generation",
                models: loadedState.imageGenerationModels,
                selection: Binding(
                    get: { loadedState.selectedImageGenerationModelId },
                    set: { sendEvent(.imageGenerationModelSelected($0)) }
                ),
                isUnavailable: loadedState.isSelectedImageModelUnavailable
            )
            if loadedState.isSelectedImageSpecialistUnsupported {
                Text(
                    "This model advertises image generation, but its mode has no supported image generation transport."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Image and Vision")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Compatible selected models may be called automatically when the chat model needs help with images."
                )
                Text("These additional requests may incur costs, depending on your provider.")
                Text("None disables delegation for that role without changing the chat model's native capabilities.")
                Text("Unavailable selections are kept until you choose another model or None.")
            }
        }
    }
}

// MARK: - Private

private extension ImageAndVisionSection {
    func modelPicker(
        _ title: LocalizedStringKey,
        models: [LLMModel],
        selection: Binding<String?>,
        isUnavailable: Bool
    ) -> some View {
        Picker(title, selection: selection) {
            Text("None")
                .tag(String?.none)
            if isUnavailable, let modelId = selection.wrappedValue {
                Text("\(modelId) (Unavailable)")
                    .tag(String?.some(modelId))
                    .disabled(true)
            }
            ForEach(models) { model in
                Text(verbatim: model.id)
                    .tag(String?.some(model.id))
            }
        }
        .pickerStyle(.menu)
#if os(iOS)
        .frame(minHeight: 44)
#endif
    }
}

#Preview("No Selection") {
    Form {
        ImageAndVisionSection(
            loadedState: .init(models: [
                LLMModel(id: "vision-model", capabilities: [.vision]),
                LLMModel(id: "image-model", mode: .imageGeneration)
            ]),
            sendEvent: { _ in }
        )
    }
}

#Preview("Unavailable Selections") {
    Form {
        ImageAndVisionSection(
            loadedState: .init(
                selectedVisionModelId: "missing-vision-model",
                selectedImageGenerationModelId: "missing-image-model"
            ),
            sendEvent: { _ in }
        )
    }
}

#Preview("Shared Native Capabilities") {
    Form {
        ImageAndVisionSection(
            loadedState: .init(
                models: [LLMModel(id: "multimodal-chat", capabilities: [.vision, .imageGeneration])],
                selectedVisionModelId: "multimodal-chat",
                selectedImageGenerationModelId: "multimodal-chat"
            ),
            sendEvent: { _ in }
        )
    }
}
