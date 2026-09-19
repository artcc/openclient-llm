# Architecture

OpenClient follows **MVVM + UseCase + Repository + Manager** with Swift strict concurrency and `async/await`.

```
View → ViewModel → UseCase → Repository → APIClient / LocalStorage
          │            │          │
          └────────────┴──────────→ Manager (transversal services)
```

## Project Structure

```
openclient-llm/                    # iOS target
├── App/
├── Shared/                        # Shared code (iOS + macOS)
│   ├── Features/
│   │   ├── AudioTranscription/
│   │   │   ├── Models/
│   │   │   ├── Repositories/
│   │   │   └── UseCases/
│   │   ├── Chat/
│   │   │   ├── Models/
│   │   │   ├── Repositories/
│   │   │   ├── Tools/
│   │   │   ├── UseCases/
│   │   │   ├── ViewModels/
│   │   │   └── Views/
│   │   ├── Home/
│   │   │   ├── UseCases/
│   │   │   ├── ViewModels/
│   │   │   └── Views/
│   │   ├── ImageGeneration/
│   │   │   ├── Models/
│   │   │   ├── Repositories/
│   │   │   └── UseCases/
│   │   ├── Launch/
│   │   │   ├── UseCases/
│   │   │   ├── ViewModels/
│   │   │   └── Views/
│   │   ├── Models/
│   │   │   ├── Models/
│   │   │   ├── Repositories/
│   │   │   ├── UseCases/
│   │   │   ├── ViewModels/
│   │   │   └── Views/
│   │   ├── Onboarding/
│   │   │   ├── Models/
│   │   │   ├── Repositories/
│   │   │   ├── UseCases/
│   │   │   ├── ViewModels/
│   │   │   └── Views/
│   │   ├── PromptTemplates/
│   │   │   ├── Models/
│   │   │   ├── Repositories/
│   │   │   ├── UseCases/
│   │   │   ├── ViewModels/
│   │   │   └── Views/
│   │   ├── Settings/
│   │   │   ├── Models/
│   │   │   ├── UseCases/
│   │   │   ├── ViewModels/
│   │   │   └── Views/
│   │   ├── Shortcuts/             # AppIntents and AppShortcutsProvider
│   │   └── TextToSpeech/
│   │       ├── Models/
│   │       ├── Repositories/
│   │       └── UseCases/
│   ├── Core/
│   │   ├── Extensions/
│   │   │   ├── Foundation/
│   │   │   └── SwiftUI/
│   │   ├── Managers/              # ShareManager, SpotlightManager, ShortcutManager…
│   │   ├── Models/                # App-side share payload and other core models
│   │   ├── Networking/
│   │   │   └── Models/
│   │   ├── Tips/
│   │   ├── Utils/
│   │   └── Views/
│   └── Resources/
└── Resources/

openclient-llm-macOS/              # macOS target
├── App/
├── Views/
└── Resources/

ShareExtension/                    # iOS Share Extension target
├── App/
│   ├── ShareViewController.swift  # Entry point (SLComposeServiceViewController)
│   └── Models/
│       ├── ShareExtensionItem.swift
│       └── ShareExtensionStore.swift
└── Resources/

WidgetsShared/                     # Shared by both WidgetKit extension targets
├── App/
│   ├── WidgetsBundle.swift        # @main entry point
│   ├── Controls/
│   │   ├── WidgetsControl.swift   # NewChatControlWidget
│   │   └── NewChatControlIntent.swift
│   ├── Intents/
│   │   └── TaggedConversationsWidgetIntent.swift
│   ├── Models/
│   │   ├── AppGroupStore.swift    # Reads/writes App Group shared container
│   │   ├── WidgetControlStore.swift
│   │   └── WidgetConversation.swift
│   └── Widgets/
│       ├── NewChatWidget.swift
│       ├── SearchWidget.swift
│       ├── QuickActionsWidget.swift
│       ├── ConversationsOverviewWidget.swift
│       ├── LatestConversationWidget.swift
│       ├── PinnedConversationsWidget.swift
│       └── TaggedConversationsWidget.swift
└── Resources/

WidgetsExtension-iOS/              # Native iOS/iPadOS WidgetKit extension
└── Resources/                     # Info.plist and Data Protection/App Group entitlements

WidgetsExtension-macOS/            # Native macOS WidgetKit extension
└── Resources/                     # Info.plist and App Group entitlements

openclient-llm-test/               # Unit tests
├── Core/
│   └── Managers/
├── Features/
│   ├── AudioTranscription/
│   ├── Chat/
│   ├── Home/
│   ├── Launch/
│   ├── Models/
│   ├── Onboarding/
│   ├── PromptTemplates/
│   └── Settings/
├── Mocks/                         # Reusable protocol-backed test doubles
└── Support/                       # Shared test harnesses and infrastructure
```

The Xcode project contains six native targets: `openclient-llm`, `openclient-llm-macOS`,
`openclient-llm-test`, `ShareExtension`, `WidgetsExtension-iOS`, and `WidgetsExtension-macOS`. It resolves three Swift
packages: SwiftLintPlugins, VoticeSDK, and ConfettiSwiftUI.

## Layer Responsibilities

| Layer | Responsibility |
|---|---|
| **View** | SwiftUI views. Observes ViewModel state, sends events. No business logic. |
| **ViewModel** | `@Observable @MainActor`. Receives events through `send(_:)`; coordinates UseCases and selected Managers. Most expose a State enum; Home exposes focused observable routing properties. |
| **UseCase** | Single business operation. Calls Repositories and Managers. |
| **Repository** | Data access abstraction (network, cache, local storage). Protocol-based for testability. |
| **Manager** | Transversal storage, device, sync, routing, and SDK coordination used where needed across layers. |
| **APIClient** | Networking via `URLSession` + `async/await`; appends repository endpoint paths to the saved base URL. |

## Platform Strategy

- **`Shared/`** — Business logic, models, networking, ViewModels, UseCases, Repositories, Managers, and most views. Referenced by both app targets.
- **`openclient-llm/`** (outside Shared) — iOS/iPadOS-specific views, app entry point, iOS resources.
- **`openclient-llm-macOS/`** — macOS-specific views, app entry point, macOS resources. No shared logic duplicated here.
- **`ShareExtension/`** — iOS/iPadOS Share Extension. It owns compatible write-side payload/store types; the main app owns the read side. They exchange JSON and attachments through `group.com.artcc.openclient-llm`; the extension does not link `Shared/`.
- **`WidgetsShared/`** — Seven widgets and a New Chat control compiled into the native iOS/iPadOS and macOS widget
  extensions. The widget UI does not link the shared feature layer; both extensions read snapshots from the App Group and
  navigate through `openclient://` deep links. `AppGroupStore`, `WidgetConversation`, and `WidgetControlStore` also compile
  into both apps.
- **`WidgetsExtension-iOS/` / `WidgetsExtension-macOS/`** — Platform-owned plists and entitlements. Only the iOS extension
  enables complete Data Protection so sensitive widgets are hidden while the device is locked.
- **`#if os(iOS)` / `#if os(macOS)`** — Used inside shared views for platform-specific UI variations.

The iOS and macOS app targets set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The test and extension targets do not;
tests that access app-isolated types declare `@MainActor` explicitly.

## Share Extension Data Flow

```
Other App (Telegram, Safari…)
    └── Share Sheet → ShareViewController (extension)
                          ├── Writes ShareExtensionItem JSON → App Group container
                          ├── Writes attachment binaries   → App Group container/SharePending/
                          └── Opens openclient://share

openclient://share → SceneDelegate.handle(url:)
    └── ShareManager.shared.hasPendingShare = true

HomeView.onChange(hasPendingShare)
    └── HomeViewModel.send(.shareItemReceived)
            ├── ShareExtensionStore.load()   → reads JSON
            ├── pendingShareItem = item
            └── pendingConversation = Conversation(modelId: …)

HomeView.onChange(pendingConversation)
    └── ChatView(shareItem: item)
            └── .task → processShareItemIfNeeded()
                    ├── viewModel.send(.inputChanged(text/url))
                    ├── viewModel.send(.attachmentAdded(…)) per binary
                    └── ShareExtensionStore.clear()
```

## Widget Data Flow

```text
ConversationRepository
    ├── Builds lightweight recent, pinned, and tagged snapshots
    ├── AppGroupStore → group.com.artcc.openclient-llm
    └── WidgetCenter.reloadTimelines(ofKind:)

WidgetsExtension-iOS / WidgetsExtension-macOS
    ├── Read WidgetConversation snapshots from AppGroupStore
    ├── Render the shared WidgetsShared views and providers
    └── Open openclient://new-chat, search, or conversation deep links

NewChatControlWidget
    └── WidgetControlStore.requestNewChat()
            └── App lifecycle activation consumes the request
                    └── ShortcutManager.pendingAction = .newChat
```
