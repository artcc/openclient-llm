//
//  FeatureTips.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
import TipKit

struct ModelSelectorTip: Tip {
    var title: Text { Text(String(localized: "Choose the right model")) }

    var message: Text? {
        Text(String(localized: "Each conversation can use a different model. Features depend on its capabilities."))
    }
}

struct ChatAttachmentsTip: Tip {
    var title: Text { Text(String(localized: "Add images and documents")) }

    var message: Text? {
#if os(macOS)
        Text(String(localized: "Attach an image or PDF, or drag files into the chat for the model to analyse."))
#else
        Text(String(localized: "Attach a photo or PDF so the model can analyse its content."))
#endif
    }
}

struct MessageActionsTip: Tip {
    var title: Text { Text(String(localized: "More actions for messages")) }

    var message: Text? {
#if os(macOS)
        Text(String(
            localized: "Use the message actions button to edit, regenerate, branch, or save it as a favourite.")
        )
#else
        Text(String(
            localized: "Tap the message actions button to edit, regenerate, branch, or save it as a favourite.")
        )
#endif
    }
}

struct WebSearchTip: Tip {
    var title: Text { Text(String(localized: "Search the web")) }

    var message: Text? {
        Text(String(localized: "Let the model find current information and include the sources it used."))
    }
}

struct ChatOptionsTip: Tip {
    var title: Text { Text(String(localized: "Customise this conversation")) }

    var message: Text? {
        Text(String(localized: "Find conversation settings, favourites, files, and export options in this menu."))
    }
}

struct ContextUsageTip: Tip {
    var title: Text { Text(String(localized: "Keep track of context")) }

    var message: Text? {
        Text(String(
            localized: "OpenClient may summarise or exclude older messages without removing them from your history."
        ))
    }
}

struct PrivateChatTip: Tip {
    var title: Text { Text(String(localized: "Start a private chat")) }

    var message: Text? {
        Text(String(
            localized: "Private chats are not saved or synced, and they do not read or change personal memory."
        ))
    }
}

struct ConversationOrganizationTip: Tip {
    var title: Text { Text(String(localized: "Organise your conversations")) }

    var message: Text? {
#if os(macOS)
        Text(String(localized: "Right-click a conversation to pin, rename, or add tags."))
#else
        Text(String(localized: "Touch and hold a conversation to pin, rename, or add tags."))
#endif
    }
}

struct MemoryTip: Tip {
    var title: Text { Text(String(localized: "Control what the model remembers")) }

    var message: Text? {
        Text(String(localized: "Review, edit, disable, or delete the memories used in future conversations."))
    }
}

struct MCPServersTip: Tip {
    var title: Text { Text(String(localized: "Connect external tools")) }

    var message: Text? {
        Text(String(localized: """
            Enable tools from MCP servers like GitHub, databases, \
            and more to let the model work with external services.
            """))
    }
}

struct AppIconSelectionTip: Tip {
    var title: Text { Text(String(localized: "Choose your app icon")) }

    var message: Text? {
        Text(String(localized: "Pick an OpenClient icon that matches your style."))
    }
}
