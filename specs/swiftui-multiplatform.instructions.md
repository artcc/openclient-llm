---
description: "Use when creating or modifying SwiftUI views, building multi-platform UI, adapting layouts for iOS/iPadOS/macOS, or working with platform-specific navigation and controls."
applyTo: "**/*.swift"
---

# SwiftUI Multi-Platform Patterns

## Platform Adaptation

Use conditional compilation for platform-specific UI:

```swift
#if os(iOS)
// iPhone-specific layout
#elseif os(macOS)
// macOS-specific layout (sidebar, toolbar, menu bar)
#endif
```

Shared views and logic live in `openclient-llm/Shared/`. The repository has no `openclient-llm/Views/` directory. The
macOS target compiles Shared and adds only genuinely macOS-specific app, menu bar, and commands UI from
`openclient-llm-macOS/`.

For shared views that differ slightly by platform, use `#if os()` inside the view. Only create separate view files per target when the UI is fundamentally different.

## View Structure

- One View per file, named after the view
- Primary screens and reusable visual components need preview coverage, either in the same file or a dedicated
  `Type+Previews.swift` file. Platform adapters and infrastructure-only views may rely on a composed parent preview
- Use `@State` for view-local state, `@Environment` for injected dependencies
- Use `@Observable` view models injected via `@State private var` in the view
- Views switch on `viewModel.state` to render `.loading` / `.loaded` states
- Use `.task {}` instead of `.onAppear` for async loading

```swift
struct ChatView: View {
    // MARK: - Properties

    @State private var viewModel = ChatViewModel()

    // MARK: - View

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
            case .loaded:
                // Feature content
            }
        }
        .task {
            viewModel.send(.viewAppeared)
        }
    }
}

// MARK: - Private

private extension ChatView {}

#Preview {
    ChatView()
}
```

## Navigation

> **Generic vs. App-Specific**: Navigation patterns below are generic. The specific tab names, icons, and sidebar structure are marked as **app-specific** and should be adapted per project.

### iOS / iPadOS - Current Tab Bar

The app uses a `TabView` with Liquid Glass style as the root navigation on iOS and iPadOS. The Tab Bar gets Liquid Glass automatically with the iOS 26+ SDK.

> **App-Specific** — Adapt tab names, icons, and content for your project.

| Tab | SF Symbol | Content |
|---|---|---|
| **Chats** | `bubble.left.and.bubble.right` | Conversation list + chat view (`NavigationStack`) |
| **Models** | `brain.head.profile` | Available models from the configured server |
| **Settings** | `gearshape` | Server configuration, API key, preferences |
| **Search** | `magnifyingglass` | Dedicated conversation search, using `role: .search` |

> **App-Specific** — Adapt tab structure for your project.

```swift
TabView(selection: $selectedTab) {
    Tab(value: AppTab.chats) {
        ChatsNavigationView()
    } label: {
        Label(String(localized: "Chats"), systemImage: "bubble.left.and.bubble.right")
    }
    Tab(value: AppTab.models) {
        ModelsView()
    } label: {
        Label(String(localized: "Models"), systemImage: "brain.head.profile")
    }
    Tab(value: AppTab.settings) {
        SettingsView()
    } label: {
        Label(String(localized: "Settings"), systemImage: "gearshape")
    }
    Tab(value: AppTab.search, role: .search) {
        SearchConversationsView()
    } label: {
        Label(String(localized: "Search"), systemImage: "magnifyingglass")
    }
}
.tabViewStyle(.sidebarAdaptable)
```

- `HomeView` uses `.tabViewStyle(.sidebarAdaptable)` and each destination owns navigation where needed.
- Current iPadOS behavior uses the same iOS `NavigationStack` chat layout; it does not contain a separate
  `NavigationSplitView` implementation.
- iPad sidebar search uses a `tabViewSidebarHeader` field and renders conversation search results in the main area.
  The Search tab remains available in the top-bar layout. Query text persists when opening a result in Chats;
  an empty iPad query shows search guidance instead of the entire conversation list.
- Tabs are scalable — future features (e.g., "Images" for image generation) can be added as new tabs

### macOS — NavigationSplitView with Sidebar

macOS does **not** use Tab Bar. Instead, use `NavigationSplitView` with a sidebar as the root navigation:

- Sidebar contains Chats, Models, and Settings destinations.
- The Chats detail owns a `NavigationStack` with the conversation list and chat navigation.
- Search is not a macOS sidebar destination in the current implementation.
- Use toolbar items and keyboard shortcuts for macOS-native interaction

### Navigation Destinations

- Define navigation destinations with enums conforming to `Hashable`
- Use `NavigationStack` with typed `NavigationPath` for push navigation within each tab/section

## Layout Guidelines

- **iOS**: `TabView` (Liquid Glass) as root → `NavigationStack` inside each tab
- **iPadOS**: Same `.sidebarAdaptable` `TabView` and Chats `NavigationStack` as iPhone; let SwiftUI adapt the tab chrome
- **macOS**: `NavigationSplitView` with sidebar, toolbar items, keyboard shortcuts — no Tab Bar

## Reusable Components & Custom Modifiers

### Custom Views

- When a piece of UI is used in more than one place, extract it into a **custom reusable View** (e.g., `LoadingButton`, `ErrorBanner`, `APIKeyField`)
- Place cross-feature shared views in `openclient-llm/Shared/Core/Views/`; feature-owned views stay under
  `openclient-llm/Shared/Features/<Feature>/Views/`.
- Custom views must be self-contained: receive data through initializer parameters, not by reaching into parent state
- Reusable visual components need preview coverage, either in the same file or a dedicated `Type+Previews.swift` file

### Custom ViewModifiers

- When the same combination of modifiers is applied in multiple places, create a **custom `ViewModifier`** (e.g., `.urlFieldStyle()`, `.cardStyle()`)
- Keep feature-only modifiers beside the feature (for example, Chat view modifiers currently live under Chat `Views/`).
  Create `Shared/Core/Modifiers/` only when a genuinely cross-feature modifier warrants that directory.
- Provide a convenience `View` extension for each modifier:
  ```swift
  struct URLFieldModifier: ViewModifier {
      func body(content: Content) -> some View {
          content
              .textContentType(.URL)
              .autocorrectionDisabled()
              #if os(iOS)
              .textInputAutocapitalization(.never)
              .keyboardType(.URL)
              #endif
      }
  }

  extension View {
      func urlFieldStyle() -> some View {
          modifier(URLFieldModifier())
      }
  }
  ```
- Prefer a custom modifier over repeating 3+ identical modifiers across views
- Keep modifiers focused on a single responsibility — don't create "god modifiers" that do too much

## Common Patterns

- Use `.task {}` modifier for async data loading on view appear
- Use `ViewThatFits` or `GeometryReader` sparingly for adaptive layouts
- Prefer built-in SwiftUI components over custom implementations
- Use `.searchable()` for search functionality
- Use `.sheet()`, `.popover()`, `.confirmationDialog()` for modal presentations
- For chat programmatic scrolling, use `ScrollViewReader`, explicit sentinels, semantic layout revisions, and scroll phase
  APIs. Never bind live scroll position or drive automatic scrolling from geometry/visibility observations; this avoids a
  macOS AttributeGraph loop when users scroll during an active response.

## Platform-Specific Control Patterns

When a shared view needs different control appearance per platform, use `#if os()` to apply platform-appropriate styles. Common divergences:

### Buttons

```swift
// Primary action — looks native on both platforms
Button("Save") { }
#if os(macOS)
    .buttonStyle(.borderedProminent)
    .controlSize(.regular)
#endif

// Secondary action inside a non-glass context
Button("Cancel") { }
#if os(macOS)
    .buttonStyle(.bordered)
#endif
```

### Text Fields

```swift
// Standalone text field (outside Form)
TextField("URL", text: $url)
#if os(macOS)
    .textFieldStyle(.roundedBorder)
#else
    .textFieldStyle(.plain)
#endif
```

### Modal Presentations

```swift
// Small contextual content
#if os(macOS)
.popover(isPresented: $showPicker) { content }
#else
.sheet(isPresented: $showPicker) { content }
#endif
```

### Conditional Padding Helper

When iOS and macOS need different spacing, define platform constants:

```swift
private extension CGFloat {
    #if os(macOS)
    static let horizontalContentPadding: CGFloat = 12
    static let verticalItemSpacing: CGFloat = 8
    #else
    static let horizontalContentPadding: CGFloat = 16
    static let verticalItemSpacing: CGFloat = 12
    #endif
}
```

---

## App-Specific Sections Summary

The following parts of this document are specific to **OpenClient**:

- **Tab Bar configuration** — Specific tabs (Chats, Models, Settings, Search), icons, and content
- **macOS sidebar structure** — Specific sidebar sections

All other sections are **generic SwiftUI multi-platform patterns** reusable across projects.
