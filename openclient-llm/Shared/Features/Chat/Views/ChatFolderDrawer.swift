//
//  ChatFolderDrawer.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

#if os(iOS)
import SwiftUI

struct ChatFolderDrawer: View {
    let history: ConversationListViewModel
    let isPresented: Bool
    let scope: ConversationFolderScope
    let onSelect: (ConversationFolderScope) -> Void
    let onClose: () -> Void

    @State private var action: MobileFolderAction?
    @AccessibilityFocusState private var isCloseFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var preferredWidth: CGFloat = 320

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if isPresented {
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()
                        .onTapGesture(perform: onClose)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    panel
                        .frame(width: max(0, min(preferredWidth, geometry.size.width - 44)))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(.background, ignoresSafeAreaEdges: [.vertical, .leading])
                        .transition(reduceMotion ? .opacity : .move(edge: .leading))
                        .zIndex(1)
                        .onAppear { isCloseFocused = true }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isPresented)
        }
        .allowsHitTesting(isPresented)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityHidden(!isPresented)
        .accessibilityAction(.escape, onClose)
        .onChange(of: isPresented) { _, presented in
            if !presented { action = nil }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Chats")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Close")
                .accessibilityFocused($isCloseFocused)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal)
            Divider()
            ScrollView {
                MobileFolderRows(history: history, scope: scope, includesAllChats: true, onSelect: onSelect) {
                    action = $0
                }
                .padding(8)
            }
        }
        .mobileFolderDialogs(history: history, action: $action, onCreateSubmitted: onClose)
    }
}

#Preview("Folders") {
    let folder = ConversationFolder(id: UUID(), name: "Design", updatedAt: .now)
    ChatFolderDrawer(history: .init(state: .loaded(.init(folders: [folder], hasLoadedFolders: true))),
                     isPresented: true, scope: .folder(folder.id), onSelect: { _ in }, onClose: {})
}

#Preview("Sidebar · Dynamic Type") {
    let folder = ConversationFolder(id: UUID(), name: "Product design and accessibility", updatedAt: .now)
    MobileFolderRows(history: .init(state: .loaded(.init(folders: [folder], hasLoadedFolders: true))),
                     scope: nil, includesAllChats: false, onSelect: { _ in }, onAction: { _ in })
        .frame(width: 300)
        .dynamicTypeSize(.accessibility2)
}
#endif
