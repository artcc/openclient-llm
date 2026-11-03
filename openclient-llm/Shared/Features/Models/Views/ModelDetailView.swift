//
//  ModelDetailView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 17/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
import TipKit

struct ModelDetailSelection: Identifiable {
    let model: LLMModel
    let serverBaseURL: String

    var id: String { model.id }
}

struct ModelDetailView: View {
    // MARK: - Properties

    let model: LLMModel
    let onSave: ([LLMModel.Capability]?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var usesAutomaticCapabilities: Bool
    @State private var selectedCapabilities: [LLMModel.Capability]

    // MARK: - Init

    init(model: LLMModel, onSave: @escaping ([LLMModel.Capability]?) -> Void) {
        self.model = model
        self.onSave = onSave
        _usesAutomaticCapabilities = State(initialValue: model.capabilityOverride == nil)
        _selectedCapabilities = State(initialValue: model.capabilities)
    }

    // MARK: - View

    var body: some View {
        Group {
            #if os(macOS)
            macOSBody
            #else
            NavigationStack {
                form
                    .navigationTitle(String(localized: "Model Info"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "Cancel")) {
                                dismiss()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Done")) {
                                save()
                            }
                        }
                    }
            }
            #endif
        }
        #if os(macOS)
        .frame(width: 700, height: 500)
        #endif
    }
}

// MARK: - Private

private extension ModelDetailView {
    #if os(macOS)
    var macOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Model Info"))
                    .font(.headline)

                Spacer()

                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Done")) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            form
        }
    }
    #endif

    var form: some View {
        Form {
            headerSection

            if model.maxInputTokens != nil || model.maxOutputTokens != nil {
                contextWindowSection
            }

            if hasPricing {
                pricingSection
            }

            providerModeSection

            capabilitiesSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                providerLogo

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.id)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.providerName.isEmpty {
                        Text(model.providerName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            #if os(iOS)
            .padding(.vertical, 8)
            #endif
        }
    }

    var contextWindowSection: some View {
        Section(String(localized: "Context Window")) {
            if let maxInput = model.maxInputTokens {
                LabeledContent(String(localized: "Input tokens")) {
                    Text(maxInput.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let maxOutput = model.maxOutputTokens {
                LabeledContent(String(localized: "Output tokens")) {
                    Text(maxOutput.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var pricingSection: some View {
        Section(String(localized: "Pricing")) {
            if let inputCost = model.inputCostPerToken, inputCost > 0 {
                LabeledContent(String(localized: "Input")) {
                    Text(String(localized: "$\(inputCost * 1_000, specifier: "%.4f") / 1K tokens"))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let outputCost = model.outputCostPerToken, outputCost > 0 {
                LabeledContent(String(localized: "Output")) {
                    Text(String(localized: "$\(outputCost * 1_000, specifier: "%.4f") / 1K tokens"))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var providerModeSection: some View {
        Section(String(localized: "Details")) {
            if !model.providerName.isEmpty {
                LabeledContent(String(localized: "Provider")) {
                    HStack(spacing: 6) {
                        Image(systemName: model.provider.icon)
                            .font(.caption)
                        Text(model.providerName)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            LabeledContent(String(localized: "Type")) {
                Text(model.mode.displayName)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var capabilitiesSection: some View {
        Section {
            Toggle(String(localized: "Automatic capabilities"), isOn: $usesAutomaticCapabilities)
                .popoverTip(usesAutomaticCapabilities ? AppTips.modelCapabilities : nil)
                .onChange(of: usesAutomaticCapabilities) { _, isAutomatic in
                    if !isAutomatic {
                        AppTips.modelCapabilities.invalidate(reason: .actionPerformed)
                    }
                }
            if usesAutomaticCapabilities {
                let detected = model.detectedCapabilities
                let capabilities = detected.isEmpty ? [LLMModel.Capability.text] : detected
                ForEach(capabilities.sorted {
                    $0.label.localizedStandardCompare($1.label) == .orderedAscending
                }, id: \.self) { capability in
                    capabilityLabel(capability)
                }
            } else {
                ForEach(LLMModel.Capability.allCases.filter { $0 != .text }.sorted {
                    $0.label.localizedStandardCompare($1.label) == .orderedAscending
                }, id: \.self) { capability in
                    Toggle(isOn: capabilityBinding(for: capability)) {
                        capabilityLabel(capability)
                    }
                }
            }
        } header: {
            Text(String(localized: "Capabilities"))
        } footer: {
            Text(String(localized: """
            Turn off automatic detection to choose this model's capabilities. Manual choices override detection \
            for this server. Open chats keep their loaded capabilities.
            """))
        }
    }

    func capabilityLabel(_ capability: LLMModel.Capability) -> some View {
        Label {
            Text(capability.label)
        } icon: {
            Image(systemName: capability.icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(capability.color)
        }
    }

    func capabilityBinding(for capability: LLMModel.Capability) -> Binding<Bool> {
        Binding(
            get: { selectedCapabilities.contains(capability) },
            set: { enabled in
                selectedCapabilities.removeAll { $0 == capability }
                if enabled { selectedCapabilities.append(capability) }
            }
        )
    }

    func save() {
        let capabilities = LLMModel.Capability.allCases.filter { $0 != .text && selectedCapabilities.contains($0) }
        onSave(usesAutomaticCapabilities ? nil : capabilities)
        dismiss()
    }

    var providerLogo: some View {
        Group {
            if let imageName = model.logoImageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: model.provider.genericLogoSystemName)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var hasPricing: Bool {
        (model.inputCostPerToken ?? 0) > 0 || (model.outputCostPerToken ?? 0) > 0
    }
}

// MARK: - LLMModel.Mode display name

private extension LLMModel.Mode {
    var displayName: String {
        switch self {
        case .chat: String(localized: "Chat")
        case .completion: String(localized: "Completion")
        case .embedding: String(localized: "Embedding")
        case .imageGeneration: String(localized: "Image Generation")
        case .audioTranscription: String(localized: "Speech to Text")
        case .audioSpeech: String(localized: "Text to Speech")
        case .unknown: String(localized: "Unknown")
        }
    }
}

#Preview {
    ModelDetailView(
        model: LLMModel(
            id: "gpt-4o",
            ownedBy: "openai",
            capabilities: [.vision, .functionCalling, .jsonSchema],
            provider: .cloud,
            mode: .chat,
            providerName: "OpenAI",
            maxInputTokens: 128_000,
            maxOutputTokens: 16_384,
            inputCostPerToken: 0.0000025,
            outputCostPerToken: 0.00001
        )
    ) { _ in }
}

#Preview("Manual capabilities") {
    var model = LLMModel(id: "Custom model")
    model.capabilityOverride = [.vision, .imageGeneration]
    return ModelDetailView(model: model) { _ in }
}
