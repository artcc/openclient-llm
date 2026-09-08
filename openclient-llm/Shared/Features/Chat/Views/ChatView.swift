//
//  ChatView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
import TipKit

struct ChatView: View {
    // MARK: - Properties

    @State var viewModel: ChatViewModel
    @State var scrollState = ChatScrollState()
    @State var renderedMessageRevision = 0
    @State var frozenMessageListState: ChatMessageListState?
    @State private var showSystemPromptSheet: Bool = false
    @State private var showModelParametersSheet: Bool = false
    @State private var showFavouritesSheet: Bool = false
    @State private var showMediaGallery: Bool = false
    @State var scrollToMessageId: UUID?
    @State private var showImagePicker: Bool = false
    @State private var showDocumentPicker: Bool = false
    @State private var showCameraPicker: Bool = false
    @State private var showImageFilePicker: Bool = false
    @State var showMCPSheet: Bool = false
    @State var showActions: Bool = false
    @State var editingMessage: ChatMessage?
    @State var editingMessageText: String = ""

    private let conversationInput: ChatConversationInput?
    var isPrivateChat: Bool
    var shareItem: ShareExtensionItem?
    var urlSchemeText: String?
    var onConversationUpdated: (() -> Void)?
    var onForkCreated: ((Conversation) -> Void)?
    var onShareItemProcessed: (() -> Void)?
    var onURLSchemeTextProcessed: (() -> Void)?
    var isMenuBarPresentation: Bool
    var presentsMCPAuthorization: Bool
    private let appReviewManager: AppReviewManagerProtocol

    // MARK: - Init

    init(
        conversation: Conversation? = nil,
        isPrivateChat: Bool = false,
        shareItem: ShareExtensionItem? = nil,
        urlSchemeText: String? = nil,
        appReviewManager: AppReviewManagerProtocol = AppReviewManager(),
        isMenuBarPresentation: Bool = false,
        presentsMCPAuthorization: Bool = true,
        viewModel: ChatViewModel? = nil,
        onConversationUpdated: (() -> Void)? = nil,
        onForkCreated: ((Conversation) -> Void)? = nil,
        onShareItemProcessed: (() -> Void)? = nil,
        onURLSchemeTextProcessed: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel ?? ChatViewModel(
            conversation: conversation,
            isPrivateChat: isPrivateChat
        ))
        conversationInput = conversation.map(ChatConversationInput.init)
        self.isPrivateChat = isPrivateChat
        self.shareItem = shareItem
        self.urlSchemeText = urlSchemeText
        self.appReviewManager = appReviewManager
        self.isMenuBarPresentation = isMenuBarPresentation
        self.presentsMCPAuthorization = presentsMCPAuthorization
        self.onConversationUpdated = onConversationUpdated
        self.onForkCreated = onForkCreated
        self.onShareItemProcessed = onShareItemProcessed
        self.onURLSchemeTextProcessed = onURLSchemeTextProcessed
    }

    // MARK: - View

    var body: some View {
#if os(macOS)
        macOSBody.mcpToolAuthorizationPresentation(
            viewModel: viewModel,
            compact: isMenuBarPresentation,
            isEnabled: presentsMCPAuthorization
        )
#else
        iOSBody.mcpToolAuthorizationPresentation(
            viewModel: viewModel,
            compact: false,
            isEnabled: presentsMCPAuthorization
        )
#endif
    }
}
// MARK: - Private

private extension ChatView {
#if os(macOS)
    var macOSBody: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .accessibilityLabel(String(localized: "Loading chat..."))
                    .tint(.secondary)
            case .loaded(let loadedState):
                loadedView(loadedState)
            }
        }
        .navigationTitle(conversationInput?.conversation.title ?? "")
        .tint(Color.appAccent)
        .toolbar {
            ToolbarItem(placement: .principal) {
                modelSelector(using: viewModel)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if case .loaded(let loadedSt) = viewModel.state {
                        let actions = menuActions(for: loadedSt)
                        menuContent(
                            actions: actions,
                            exportedData: loadedSt.isStreaming ? nil : loadedSt.exportedData
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(String(localized: "More Options"))
                .popoverTip(chatOptionsTip)
            }
        }
        .sheet(isPresented: $showSystemPromptSheet) {
            ChatSystemPromptView(
                viewModel: viewModel,
                isPresented: $showSystemPromptSheet
            )
        }
        .sheet(isPresented: $showModelParametersSheet) {
            ChatModelParametersView(
                viewModel: viewModel,
                isPresented: $showModelParametersSheet
            )
        }
        .sheet(isPresented: $showFavouritesSheet) {
            if case .loaded(let loadedSt) = viewModel.state {
                ChatFavouritesView(
                    messages: loadedSt.messages,
                    onMessageSelected: { id in scrollToMessageId = id }
                )
#if os(macOS)
                .frame(width: 500, height: 460)
#endif
            }
        }
        .sheet(isPresented: $showMediaGallery) {
            if case .loaded(let loadedSt) = viewModel.state {
                MediaFilesGalleryView(messages: loadedSt.messages) { scrollToMessageId = $0 }
#if os(macOS)
                    .frame(width: 500, height: 460)
#endif
            }
        }
        .sheet(isPresented: $showMCPSheet, content: mcpToolsSheet)
        .sheet(item: $editingMessage) { message in
            editMessageSheet(
                message,
                viewModel: viewModel,
                editingMessage: $editingMessage,
                editingMessageText: $editingMessageText
            )
        }
        .imagePicker(isPresented: $showImagePicker) { data, fileName, type in
            viewModel.send(.attachmentAdded(data: data, fileName: fileName, type: type))
        }
        .documentPicker(isPresented: $showDocumentPicker) { data, fileName, type in
            viewModel.send(.attachmentAdded(data: data, fileName: fileName, type: type))
        }
        .imageFilePicker(isPresented: $showImageFilePicker) { data, fileName, type in
            viewModel.send(.attachmentAdded(data: data, fileName: fileName, type: type))
        }
        .task {
            viewModel.onConversationUpdated = onConversationUpdated
            viewModel.send(.viewAppeared)
            await processShareItemIfNeeded(
                viewModel: viewModel,
                shareItem: shareItem,
                onShareItemProcessed: onShareItemProcessed
            )
            await processURLSchemeTextIfNeeded(
                viewModel: viewModel,
                urlSchemeText: urlSchemeText,
                onURLSchemeTextProcessed: onURLSchemeTextProcessed
            )
        }
        .onChange(of: conversationInput?.revision) {
            if let conversation = conversationInput?.conversation {
                viewModel.send(.conversationLoaded(conversation))
            }
        }
        .onDisappear(perform: handleViewDisappeared)
    }
#endif

    var iOSBody: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    ProgressView()
                        .accessibilityLabel(String(localized: "Loading chat..."))
                        .tint(.secondary)
                case .loaded(let loadedState):
                    loadedView(loadedState)
                }
            }
            .navigationTitle("")
            .tint(Color.appAccent)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    modelSelector(using: viewModel)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if case .loaded(let loadedSt) = viewModel.state {
                            let actions = menuActions(for: loadedSt)
                            menuContent(
                                actions: actions,
                                exportedData: loadedSt.isStreaming ? nil : loadedSt.exportedData
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(String(localized: "More Options"))
                    .popoverTip(chatOptionsTip)
                }
            }
            .sheet(isPresented: $showSystemPromptSheet) {
                ChatSystemPromptView(
                    viewModel: viewModel,
                    isPresented: $showSystemPromptSheet
                )
            }
            .sheet(isPresented: $showModelParametersSheet) {
                ChatModelParametersView(
                    viewModel: viewModel,
                    isPresented: $showModelParametersSheet
                )
            }
            .sheet(isPresented: $showFavouritesSheet) {
                if case .loaded(let loadedSt) = viewModel.state {
                    ChatFavouritesView(
                        messages: loadedSt.messages,
                        onMessageSelected: { id in scrollToMessageId = id }
                    )
                }
            }
            .sheet(isPresented: $showMediaGallery) {
                if case .loaded(let loadedSt) = viewModel.state {
                    MediaFilesGalleryView(messages: loadedSt.messages) { scrollToMessageId = $0 }
                }
            }
            .sheet(isPresented: $showMCPSheet, content: mcpToolsSheet)
            .sheet(item: $editingMessage) { message in
                editMessageSheet(
                    message,
                    viewModel: viewModel,
                    editingMessage: $editingMessage,
                    editingMessageText: $editingMessageText
                )
            }
        }
        .task {
            viewModel.onConversationUpdated = onConversationUpdated
            viewModel.onForkCreated = onForkCreated
            viewModel.send(.viewAppeared)
            await processShareItemIfNeeded(
                viewModel: viewModel,
                shareItem: shareItem,
                onShareItemProcessed: onShareItemProcessed
            )
            await processURLSchemeTextIfNeeded(
                viewModel: viewModel,
                urlSchemeText: urlSchemeText,
                onURLSchemeTextProcessed: onURLSchemeTextProcessed
            )
        }
        .onChange(of: conversationInput?.revision) {
            if let conversation = conversationInput?.conversation {
                viewModel.send(.conversationLoaded(conversation))
            }
        }
        .onDisappear(perform: handleViewDisappeared)
        .imagePicker(isPresented: $showImagePicker) { data, fileName, type in
            viewModel.send(.attachmentAdded(data: data, fileName: fileName, type: type))
        }
        .documentPicker(isPresented: $showDocumentPicker) { data, fileName, type in
            viewModel.send(.attachmentAdded(data: data, fileName: fileName, type: type))
        }
#if os(iOS)
        .cameraPicker(isPresented: $showCameraPicker) { data, fileName, type in
            viewModel.send(.attachmentAdded(data: data, fileName: fileName, type: type))
        }
#endif
    }

    func loadedView(
        _ loadedState: ChatViewModel.LoadedState
    ) -> some View {
        let messageListState = ChatMessageListState(loadedState: loadedState)
        let inputBarState = ChatInputBarState(loadedState: loadedState)
        let errorMessage = loadedState.errorMessage
        let pendingAttachments = loadedState.pendingAttachments
        return messagesScrollView(messageListState)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    errorBanner(errorMessage)
                    attachmentPreview(pendingAttachments, send: { viewModel.send($0) })
                    ChatInputBarView(
                        showImagePicker: $showImagePicker,
                        showDocumentPicker: $showDocumentPicker,
                        showCameraPicker: $showCameraPicker,
                        state: inputBarState,
                        onSend: handleSend,
                        onStopStreaming: { viewModel.send(.stopStreamingTapped) },
                        onStartRecording: { viewModel.send(.startRecordingTapped) },
                        onStopRecording: { viewModel.send(.stopRecordingTapped) },
                        onCancelRecording: { viewModel.send(.cancelRecordingTapped) },
                        onWebSearchToggled: { viewModel.send(.webSearchToggled) },
                        onMCPButtonTapped: {
                            showMCPSheet = true
                            viewModel.send(.mcpButtonTapped)
                            showActions = false
                        },
                        showActions: $showActions,
                        showImageFilePicker: $showImageFilePicker
                    )
                }
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
            }
            .modifier(ChatDropModifier(
                onText: { viewModel.send(.inputChanged($0)) },
                onAttachment: {
                    AppTips.chatAttachments.invalidate(reason: .actionPerformed)
                    viewModel.send(.attachmentAdded(data: $0, fileName: $1, type: $2))
                }
            ))
    }

    func handleViewDisappeared() {
        viewModel.send(.viewDisappeared)
        appReviewManager.requestReview()
    }

    // MARK: - Menu Content

    @ViewBuilder
    func menuContent(actions: [MenuAction], exportedData: Data?) -> some View {
        ForEach(actions) { action in
            switch action {
            case .export:
                if let exportedData, let exportedText = String(data: exportedData, encoding: .utf8) {
                    ShareLink(item: exportedText) {
                        Label(action.title, systemImage: action.systemImage)
                    }
                } else {
                    Button {
                        AppTips.chatOptions.invalidate(reason: .actionPerformed)
                        viewModel.send(.exportConversation)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            case .favourites:
                Button {
                    AppTips.chatOptions.invalidate(reason: .actionPerformed)
                    showFavouritesSheet = true
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            case .mediaFiles:
                Button {
                    AppTips.chatOptions.invalidate(reason: .actionPerformed)
                    showMediaGallery = true
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            case .modelParameters:
                Button {
                    AppTips.chatOptions.invalidate(reason: .actionPerformed)
                    showModelParametersSheet = true
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            case .systemPrompt:
                Button {
                    AppTips.chatOptions.invalidate(reason: .actionPerformed)
                    showSystemPromptSheet = true
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
        }
    }
}

#Preview { ChatView() }
