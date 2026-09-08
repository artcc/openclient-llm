//
//  ModelsView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ModelsView: View {
    // MARK: - Properties

    @State private var viewModel = ModelsViewModel()
    @State private var ttsCustomVoiceTexts: [String: String] = [:]
    @State private var ttsCustomModeActive: Set<String> = []
    @State private var modelForDetail: LLMModel?

    // MARK: - View

    var body: some View {
#if os(iOS)
        NavigationStack {
            content
        }
#else
        content
#endif
    }
}

// MARK: - Private

private extension ModelsView {
    var content: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .accessibilityLabel(String(localized: "Loading models..."))
                    .tint(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let loadedState):
                loadedView(loadedState)
            }
        }
#if os(iOS)
        .background {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
            }
        }
#endif
        .navigationTitle(String(localized: "Models"))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.send(.refreshTapped)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(String(localized: "Refresh"))
            }
        }
        .task {
            viewModel.send(.viewAppeared)
        }
        .sheet(item: $modelForDetail) { model in
            ModelDetailView(model: model)
        }
    }

    func loadedView(_ loadedState: ModelsViewModel.LoadedState) -> some View {
        Group {
            if let errorMessage = loadedState.errorMessage, loadedState.models.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Unable to Load Models"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(String(localized: "Retry")) {
                        viewModel.send(.refreshTapped)
                    }
                }
            } else {
                modelsList(loadedState)
            }
        }
    }

    func modelsList(_ loadedState: ModelsViewModel.LoadedState) -> some View {
        let chatModels = loadedState.models.filter {
            $0.mode != .audioSpeech && $0.mode != .audioTranscription
        }
        let ttsModels = loadedState.models.filter { $0.mode == .audioSpeech }
        let sttModels = loadedState.models.filter { $0.mode == .audioTranscription }
        let localModels = chatModels.filter { $0.provider == .local }
        let cloudModels = chatModels.filter { $0.provider == .cloud }

#if os(iOS)
        return List {
            modelSections(
                localModels: localModels,
                cloudModels: cloudModels,
                ttsModels: ttsModels,
                sttModels: sttModels,
                loadedState: loadedState
            )
        }
        .refreshable {
            await viewModel.refreshAsync()
        }
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
#else
        return Form {
            modelSections(
                localModels: localModels,
                cloudModels: cloudModels,
                ttsModels: ttsModels,
                sttModels: sttModels,
                loadedState: loadedState
            )
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity)
#endif
    }

    @ViewBuilder
    func modelSections(
        localModels: [LLMModel],
        cloudModels: [LLMModel],
        ttsModels: [LLMModel],
        sttModels: [LLMModel],
        loadedState: ModelsViewModel.LoadedState
    ) -> some View {
        if !localModels.isEmpty {
            Section {
                ForEach(localModels) { model in
                    modelRow(model, loadedState: loadedState)
                }
            } header: {
                modelSectionHeader(String(localized: "Local"), systemImage: "desktopcomputer", count: localModels.count)
            }
        }
        if !cloudModels.isEmpty {
            Section {
                ForEach(cloudModels) { model in
                    modelRow(model, loadedState: loadedState)
                }
            } header: {
                modelSectionHeader(String(localized: "Cloud"), systemImage: "cloud", count: cloudModels.count)
            }
        }
        if !ttsModels.isEmpty {
            Section {
                ForEach(ttsModels) { model in
                    ttsModelRow(model, loadedState: loadedState)
                }
            } header: {
                modelSectionHeader(
                    String(localized: "Text to Speech"),
                    systemImage: "waveform",
                    count: ttsModels.count
                )
            }
        }
        if !sttModels.isEmpty {
            Section {
                ForEach(sttModels) { model in
                    sttModelRow(model, loadedState: loadedState)
                }
            } header: {
                modelSectionHeader(
                    String(localized: "Speech to Text"),
                    systemImage: "waveform.badge.mic",
                    count: sttModels.count
                )
            }
        }
    }

    @ViewBuilder
    func modelSectionHeader(_ title: String, systemImage: String, count: Int) -> some View {
#if os(iOS)
        Text(title)
#else
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Text(count, format: .number)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
#endif
    }

    func modelRow(_ model: LLMModel, loadedState: ModelsViewModel.LoadedState) -> some View {
        let isSelected = model.id == loadedState.selectedModelId

        return HStack(spacing: 0) {
            Button {
                viewModel.send(.modelTapped(model))
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        providerLogo(model)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.id)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            if !model.providerName.isEmpty {
                                Text(model.providerName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    capabilityTags(model.capabilities.isEmpty ? [.text] : model.capabilities)
                        .padding(.leading, 44)
                }
#if os(iOS)
                .padding(.vertical, 6)
#else
                .padding(.vertical, 4)
#endif
                .contentShape(Rectangle())
            }
#if os(iOS)
            .buttonStyle(.plain)
#else
            .buttonStyle(.borderless)
#endif
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appAccent)
                    .font(.body.weight(.semibold))
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }

            modelInfoButton(model)
        }
    }

    func modelInfoButton(_ model: LLMModel) -> some View {
        Button {
            modelForDetail = model
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.body)
#if os(iOS)
                .frame(width: 44, height: 44)
#else
                .frame(width: 24, height: 24)
#endif
        }
#if os(iOS)
        .buttonStyle(.plain)
#else
        .buttonStyle(.borderless)
#endif
        .padding(.leading, 4)
        .accessibilityLabel(String(localized: "Model Info"))
    }

    func providerLogo(_ model: LLMModel) -> some View {
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

    func capabilityTags(_ capabilities: [LLMModel.Capability]) -> some View {
        FlowLayout(spacing: 4) {
            ForEach(capabilities.sorted { $0.label < $1.label }, id: \.self) { capability in
                HStack(spacing: 4) {
                    Image(systemName: capability.icon)
                        .font(.caption2)
                    Text(capability.label)
                        .font(.caption2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .foregroundStyle(capability.color)
                .background(capability.color.opacity(0.12), in: .capsule)
            }
        }
    }

    func ttsModelRow(_ model: LLMModel, loadedState: ModelsViewModel.LoadedState) -> some View {
        let isSelected = model.id == loadedState.selectedTTSModelId

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                viewModel.send(.ttsModelTapped(model))
            } label: {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        providerLogo(model)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.id)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            if !model.providerName.isEmpty {
                                Text(model.providerName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "waveform.circle.fill")
                                .foregroundStyle(Color.appAccent)
                                .font(.body.weight(.semibold))
                                .frame(width: 24)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
#if os(macOS)
            .buttonStyle(.borderless)
#endif
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isSelected {
                voicePicker(model: model, loadedState: loadedState)
            }
        }
        .padding(.vertical, 4)
    }

    func sttModelRow(_ model: LLMModel, loadedState: ModelsViewModel.LoadedState) -> some View {
        let isSelected = model.id == loadedState.selectedSTTModelId

        return Button {
            viewModel.send(.sttModelTapped(model))
        } label: {
            HStack(spacing: 12) {
                providerLogo(model)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.id)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if !model.providerName.isEmpty {
                        Text(model.providerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "waveform.badge.mic")
                        .foregroundStyle(Color.appAccent)
                        .font(.body.weight(.semibold))
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
        }
#if os(macOS)
        .buttonStyle(.borderless)
#endif
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    func voicePicker(model: LLMModel, loadedState: ModelsViewModel.LoadedState) -> some View {
        let voicePresets = TTSVoice.presets.map(\.rawValue)
        let currentVoice = loadedState.selectedTTSVoices[model.id] ?? TTSVoice.alloy.rawValue
        let isPresetVoice = voicePresets.contains(currentVoice)
        let showCustomInput = ttsCustomModeActive.contains(model.id) || !isPresetVoice

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Voice"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                voiceMenu(
                    model: model,
                    voicePresets: voicePresets,
                    currentVoice: currentVoice,
                    isPresetVoice: isPresetVoice
                )
            }
            if showCustomInput {
                voiceCustomField(model: model, currentVoice: currentVoice, isPresetVoice: isPresetVoice)
            }
        }
        .padding(.top, 8)
        .padding(.leading, 44)
#if os(macOS)
        .controlSize(.small)
#endif
    }

    func voiceMenu(
        model: LLMModel,
        voicePresets: [String],
        currentVoice: String,
        isPresetVoice: Bool
    ) -> some View {
        Menu {
            ForEach(voicePresets, id: \.self) { preset in
                Button {
                    viewModel.send(.voiceSelected(preset, forModelId: model.id))
                    ttsCustomVoiceTexts.removeValue(forKey: model.id)
                    ttsCustomModeActive.remove(model.id)
                } label: {
                    if currentVoice == preset {
                        Label(preset.capitalized, systemImage: "checkmark")
                    } else {
                        Text(preset.capitalized)
                    }
                }
                .accessibilityAddTraits(currentVoice == preset ? .isSelected : [])
            }
            Divider()
            Button(String(localized: "Custom...")) {
                ttsCustomModeActive.insert(model.id)
                if !isPresetVoice {
                    ttsCustomVoiceTexts[model.id] = currentVoice
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(isPresetVoice && !ttsCustomModeActive.contains(model.id)
                     ? currentVoice.capitalized
                     : String(localized: "Custom..."))
                .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.appAccent)
#if os(iOS)
            .frame(minHeight: 44)
#endif
        }
    }

    func voiceCustomField(model: LLMModel, currentVoice: String, isPresetVoice: Bool) -> some View {
        TextField(
            String(localized: "Voice ID"),
            text: Binding(
                get: { ttsCustomVoiceTexts[model.id] ?? (isPresetVoice ? "" : currentVoice) },
                set: { ttsCustomVoiceTexts[model.id] = $0 }
            )
        )
        .textFieldStyle(.roundedBorder)
        .font(.subheadline)
        .onSubmit {
            let text = ttsCustomVoiceTexts[model.id] ?? ""
            guard !text.isEmpty else { return }
            viewModel.send(.voiceSelected(text, forModelId: model.id))
            ttsCustomVoiceTexts.removeValue(forKey: model.id)
            ttsCustomModeActive.remove(model.id)
        }
    }
}

#Preview {
    ModelsView()
}
