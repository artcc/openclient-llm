---
description: "Use when designing UI, choosing colors, applying Liquid Glass style, configuring Dark Mode, adding SF Symbols, handling accessibility, haptics, or animations in SwiftUI views."
applyTo: "**/*.swift"
---

# Design & UI Guidelines

## Design Philosophy

Native-first design. The app should feel like a first-party Apple app, leveraging system components and platform conventions.

> **Generic vs. App-Specific**: This document contains both generic Apple design guidelines (reusable across projects) and app-specific configuration for OpenClient. Sections marked with **"App-Specific"** should be adapted when reusing these guidelines in other projects. See the summary at the bottom for a full list.

## Liquid Glass (iOS 26+ / macOS 26+)

### Core Guidelines

- Prefer native Liquid Glass APIs over custom blurs or materials
- Use `GlassEffectContainer` when multiple glass elements coexist in the same view
- Apply `.glassEffect(...)` **after** layout and visual modifiers (padding, frame, font, foregroundStyle)
- Use `.interactive()` only for elements that respond to touch or pointer (buttons, tappable chips)
- Keep shapes consistent across related glass elements for a cohesive look
- Navigation bars, tab bars, and toolbars get Liquid Glass automatically with the iOS 26 SDK — don't add manual glass to them
- Test with varied wallpapers to ensure readability over different backgrounds

### API Reference

#### Glass surfaces

```swift
Text("Label")
    .padding()
    .glassEffect(.regular, in: .rect(cornerRadius: 16))
```

#### Interactive glass (tappable elements)

```swift
Text("Tappable")
    .padding()
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
```

#### Tinted glass

```swift
Text("Tinted")
    .padding()
    .glassEffect(.regular.tint(.accent).interactive(), in: .rect(cornerRadius: 16))
```

#### Grouped glass elements

```swift
GlassEffectContainer(spacing: 24) {
    HStack(spacing: 24) {
        Image(systemName: "scribble.variable")
            .frame(width: 72, height: 72)
            .font(.system(size: 32))
            .glassEffect()
        Image(systemName: "eraser.fill")
            .frame(width: 72, height: 72)
            .font(.system(size: 32))
            .glassEffect()
    }
}
```

#### Glass button styles

```swift
Button("Action") { }
    .buttonStyle(.glass)

Button("Primary Action") { }
    .buttonStyle(.glassProminent)
```

#### Morphing transitions

```swift
@Namespace private var glassNamespace

// Use glassEffectID for animated transitions between glass elements
view.glassEffect(.regular, in: .capsule)
    .glassEffectID("elementID", in: glassNamespace)
```

### Availability Gating

The app targets iOS 26 and macOS 26, so use Liquid Glass APIs directly. Add availability checks and a fallback only if a
target's deployment version is lowered.

```swift
if #available(iOS 26, *) {
    Text("Hello")
        .padding()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
} else {
    Text("Hello")
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
}
```

> **Note**: Since the project minimum deployment is iOS 26, availability checks are only needed if we ever lower the target. For now, use glass APIs directly without `#available`.

### Review Checklist

When reviewing or adding Liquid Glass to a view, verify:

1. **Composition**: Multiple glass views wrapped in `GlassEffectContainer`
2. **Modifier order**: `glassEffect` applied after layout/appearance modifiers
3. **Interactivity**: `.interactive()` only where user interaction exists
4. **Transitions**: `glassEffectID` used with `@Namespace` for morphing animations
5. **Consistency**: Shapes, tinting, and spacing align across the feature
6. **No double glass**: Don't add glass to system components that already have it (NavigationBar, TabBar, Toolbar)

## Color System

### Principles

- **Always use semantic colors** from Asset Catalog — never hardcoded hex/RGB values
- Define colors with both Light and Dark appearance variants in the Asset Catalog
- Use system colors (`Color.primary`, `Color.secondary`, `Color.accentColor`) as base
- Custom colors should be high-contrast and accessible in both modes
- Use `Color(.systemBackground)`, `Color(.secondarySystemBackground)` for surfaces

### Current App Assets

> **App-Specific** — Adapt this palette for your project.

`Shared/Resources/Assets.xcassets` currently contains `AccentColor`, legacy chat colors (`UserBubble`,
`UserBubbleText`, `AssistantBubble`, `AssistantBubbleText`, `CodeBlockBackground`), the app logo, and raster provider
logos. Do not document exact RGB values unless they are verified from the asset catalog.

Current chat UI primarily uses `Color.appAccent`, semantic foreground styles, tinted glass for the user bubble, no
assistant bubble background, and `.ultraThinMaterial` for code blocks. Existing color assets do not imply every one is
actively used.

### Usage Rules

- **Accent color** is the only branded color — everything else uses system semantics
- **Message bubbles**: User = accent-tinted glass (right-aligned); Assistant = unboxed content (left-aligned)
- **Surfaces**: Always `Color(.systemBackground)` and `Color(.secondarySystemBackground)` — never custom background colors
- **Text**: Always `Color.primary` / `Color.secondary` except inside colored user bubbles (fixed white)
- **Destructive actions**: Always `Color.red` (system) — never custom reds
- When in doubt, use a system color over a custom one

## Typography

- Use semantic system fonts for most UI.
- Poppins is bundled under `Shared/Resources/Fonts` and exposed through `Font.poppins`. Current code uses it selectively
  for onboarding display text, the chat greeting/model selector, and a conversation badge. Preserve that accent rather
  than claiming the app is system-font-only.
- Pair custom font sizes with `relativeTo:` so Dynamic Type can scale them. Fixed SF Symbol sizes are acceptable where
  the icon has a constrained visual role.
- Use `@ScaledMetric` for spacing that should scale with text size
- Prefer `Text` view with system font styles over custom attributed strings

## Icons

- Prefer SF Symbols for controls, navigation, status, and generic concepts.
- The app intentionally uses custom image assets for its logo and model-provider branding. Do not replace recognizable
  provider artwork with a generic SF Symbol merely to satisfy an all-SF-Symbol rule.
- Apply symbol rendering modes: `.monochrome`, `.hierarchical`, `.palette`, `.multicolor`
- Use symbol effects for animations: `.symbolEffect(.bounce)`, `.symbolEffect(.pulse)`
- Prefer `.symbolVariant(.fill)` for selected/active states

## Dark Mode

- **System-only**: The app follows the system appearance setting — there is no in-app light/dark toggle
- Always test both Light and Dark appearances
- Use semantic colors and system materials — they adapt automatically
- Images should use template rendering where appropriate
- Asset Catalog images can have Light/Dark variants when needed
- Never use `preferredColorScheme()` to force a specific appearance

## Accessibility

- Add `.accessibilityLabel()` to all interactive elements without visible text
- Support **VoiceOver** navigation with logical reading order
- Use `.accessibilityHint()` for non-obvious actions
- Ensure minimum touch target of 44×44pt on iOS
- Test with larger text sizes (Accessibility Inspector)

## Haptics (iOS only)

- Use `UIImpactFeedbackGenerator` for action feedback (send message, button taps)
- Use `UINotificationFeedbackGenerator` for success/error/warning states
- Keep haptics subtle — don't overuse
- Guard with `#if os(iOS)` — no haptics on macOS

## macOS-Specific Design

macOS has different visual expectations than iOS. The same SwiftUI code can look out of place on Mac if it uses iOS-centric patterns. Follow these rules to ensure a native macOS feel.

### Button Styles

- **Never** use `.buttonStyle(.plain)` for standard macOS actions — it removes the native button chrome and looks broken
- Use `.buttonStyle(.bordered)` as the default for secondary/standard buttons on macOS
- Use `.buttonStyle(.borderedProminent)` for primary/call-to-action buttons
- Use `.buttonStyle(.glass)` or `.buttonStyle(.glassProminent)` only for elements inside Liquid Glass contexts (toolbars, floating panels)
- Use `.buttonStyle(.plain)` only for inline/invisible tap targets (e.g., icons inside custom rows)
- Apply platform-specific button styles with `#if os()` when iOS and macOS need different treatments:

```swift
Button("Action") { }
#if os(macOS)
    .buttonStyle(.bordered)
#else
    .buttonStyle(.plain)
#endif
```

### Control Sizes

- macOS supports `.controlSize()` which significantly impacts visual density:
  - `.controlSize(.small)` — Use in toolbars, sidebars, compact lists
  - `.controlSize(.regular)` — Default for most content areas
  - `.controlSize(.large)` — Use for primary actions in onboarding or prominent forms
- Apply `.controlSize()` at the container level (e.g., on a `Form` or `VStack`) to affect all children
- iOS ignores `.controlSize()` — safe to apply unconditionally but prefer `#if os(macOS)` for clarity

### Spacing & Padding

- macOS uses more compact spacing than iOS — information density is expected on desktop
- Use platform-conditional padding when a view feels too spread out on Mac:

```swift
.padding(.horizontal, platformHorizontalPadding)

// Define as computed property or constant:
#if os(macOS)
private let platformHorizontalPadding: CGFloat = 12
#else
private let platformHorizontalPadding: CGFloat = 16
#endif
```

- Sidebar items: 8-10pt vertical padding (macOS) vs 12-14pt (iOS)
- Form rows: macOS uses native `Form` spacing — don't override it
- List rows: macOS uses tighter default spacing — respect it

### Forms & Settings

- On macOS, `Form` renders as a grouped macOS-style form automatically — don't wrap in custom containers
- `Toggle`, `Picker`, `TextField` inside `Form` on macOS get native AppKit-style rendering
- Don't add custom backgrounds or glass effects to form controls on macOS — they already have system chrome
- Use `LabeledContent` for read-only form rows on macOS
- `.textFieldStyle(.roundedBorder)` on macOS for standalone text fields outside of Forms

### Sheets & Popovers

- On macOS, prefer `.popover()` over `.sheet()` for small contextual content (pickers, confirmations)
- `.sheet()` on macOS renders as a floating window-attached sheet — use for multi-step flows or larger forms
- `.confirmationDialog()` renders as a native macOS alert sheet — use for destructive confirmations
- Size sheets explicitly on macOS with `.frame(width:height:)` inside the sheet content — macOS sheets don't auto-size as gracefully as iOS
- Avoid full-screen covers (`.fullScreenCover()`) on macOS — they don't exist; use `.sheet()` instead

### Toolbar & Menu Bar

- macOS toolbars have built-in Liquid Glass — don't add extra glass to toolbar content
- Use `ToolbarItem(placement: .automatic)` on macOS — specific placements like `.navigationBarTrailing` don't exist
- Toolbar buttons on macOS should use SF Symbols with `.label` style (icon + text) for discoverability
- Add keyboard shortcuts to frequently used actions via `.keyboardShortcut()`:

```swift
Button("New Chat") { }
    .keyboardShortcut("n", modifiers: .command)
```

### Scroll & Content Areas

- macOS scroll views have elastic bouncing and scroll bars — respect system defaults
- Don't hide scroll indicators on macOS — users expect visible scroll bars
- Use `.scrollContentBackground(.visible)` on macOS Lists to keep the native background
- Avoid `.scrollDismissesKeyboard()` on macOS — it's iOS-only behavior

### Hover Effects

- macOS supports hover states — use `.onHover()` for interactive feedback:
  - Highlight list rows on hover
  - Show secondary actions on hover (e.g., timestamp on message hover)
- Prefer subtle background change or opacity shift over bold color changes
- Don't use `.onHover()` on iOS — it's ignored on touch devices

### Focus & Keyboard Navigation

- macOS users navigate with Tab key — ensure logical focus order
- Use `.focusable()` and `.focused()` for keyboard-navigable custom controls
- Highlight focused elements with a visible focus ring (system default)

## Animations

- Use SwiftUI built-in transitions and animations (`.animation()`, `withAnimation {}`)
- Prefer `.spring()` or `.smooth` for natural motion
- Use `matchedGeometryEffect` for shared element transitions
- Keep animations fast (0.2-0.35s) — never block interaction
- Avoid custom animations when a system component handles it natively
- Preserve feature-specific motion instead of imposing one global transition: onboarding uses `.smooth` and springs,
  input state changes use spring/push/opacity transitions, and chat messages currently insert with opacity only.

## App Navigation Structure

> **App-Specific** — Adapt tabs, sidebar sections, and navigation hierarchy for your project.

### iOS / iPadOS

- Root navigation is a `.sidebarAdaptable` `TabView` with four destinations.
- **Chats** uses `bubble.left.and.bubble.right`.
- **Models** uses `brain.head.profile`.
- **Settings** uses `gearshape`.
- **Search** uses `magnifyingglass` and `role: .search`.
- Chats and Search own `NavigationStack` navigation. Models and Settings own their screen navigation as implemented.
- iPadOS currently uses the same layout and SwiftUI's adaptive tab style; there is no separate Chats
  `NavigationSplitView` implementation.

### macOS

- Root navigation: `NavigationSplitView` with sidebar (no Tab Bar)
- Sidebar shows Chats, Models, and Settings. Search is not a macOS sidebar destination.
- Liquid Glass applies to sidebar and toolbar automatically

## App Flow

> **App-Specific** — Adapt the entry point, onboarding, and routing for your project.

The app has a single entry point (`LaunchView`) that routes based on onboarding state:

```
LaunchView
├── isOnboardingCompleted == false → OnboardingView
│   ├── Step 1: Welcome (app intro + "Get Started" button)
│   ├── Step 2: Server Configuration (base URL + API key + Test Connection)
│   └── Step 3: All Set (confirmation + "Start Chatting" button)
│       └── Saves isOnboardingCompleted = true → HomeView
└── isOnboardingCompleted == true → HomeView (TabView / NavigationSplitView)
```

### LaunchView Rules

- `LaunchView` is the **root view** in both iOS and macOS app entry points
- It reads `isOnboardingCompleted` from `SettingsManager` (UserDefaults)
- No animation on initial routing — instant switch
- After onboarding completes, transition to `HomeView` with a smooth animation

### OnboardingView Rules

- Full-screen flow, no Tab Bar or navigation chrome visible
- Step indicator (dots or progress) at the top
- "Back" button available from Step 2 and 3 (not Step 1)
- **"Skip" button** visible on all steps — user can skip the entire onboarding
- If skipped, `isOnboardingCompleted = true` is still saved, and the user goes directly to `HomeView`
- When skipped, server configuration fields remain empty — the app shows the Settings tab with a prompt to configure the server
- Step 2 must validate server connection before allowing "Next" (but skip bypasses this)
- On completion, persist `isOnboardingCompleted = true` and route to `HomeView`
- User can always configure or reconfigure the server later from Settings

### HomeView Rules

- `HomeView` is the main shell — it hosts `TabView` (iOS/iPadOS) or `NavigationSplitView` (macOS)
- `HomeView` is never wrapped in another `NavigationStack` — each tab manages its own
- Default selected tab on launch: **Chats**

## macOS Window

> **App-Specific** — Adapt window sizes for your project.

### Current Size

- `LaunchView` has a minimum size of **800×600 pt**.
- `WindowGroup(id: "main")` has a default size of **800×600 pt**.
- The app does not currently apply `.windowResizability(.contentSize)`.

### Persist Window Size & Position

- The app must remember the user's window size and position across launches
- Use `WindowGroup` with a stable identifier so macOS restores state automatically:

```swift
// macOS App entry point
@main
struct OpenClientApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            LaunchView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 800, height: 600)
    }
}
```

- macOS automatically persists window frame for `WindowGroup` with a stable `id` — no manual `UserDefaults` saving needed
- Do **not** allow the window to resize below the minimum size

## Toolbar Patterns

> **App-Specific** (table below) — Adapt per-screen toolbar actions for your project.

Define standard toolbar actions per screen to keep the UI consistent:

| Screen | Leading | Center / Title | Trailing |
|---|---|---|---|
| **Chats list** | — | "Chats" title | New Chat menu (`square.and.pencil`), backup import/export actions |
| **Chat detail** | Back (auto) | Model name (subtitle style) | Chat info/options (`ellipsis.circle`) |
| **Models list** | — | "Models" title | Refresh button (`arrow.clockwise`) |
| **Settings** | — | "Settings" title | — |
| **Onboarding** | Back (Step 2+) | Step indicator | Skip button |

### Implementation Rules

- Use `.toolbar {}` with `ToolbarItem(placement:)` — never custom HStacks in the navigation bar
- On macOS, add keyboard shortcuts to toolbar actions (e.g., `⌘N` for New Chat)
- Keep toolbar items minimal — max 2-3 per screen
- Use SF Symbols for all toolbar icons

## Search

Current implementation:

- iOS/iPadOS has a dedicated Search tab backed by `SearchConversationsView`.
- It uses local conversation filtering through `ConversationListViewModel`, `.searchable`, and
  `ContentUnavailableView.search` for no matches.
- iOS places the field in an always-visible navigation bar drawer; macOS uses default searchable placement when this
  shared view is presented.
- The macOS conversation list also has its own toolbar search expansion.
- iPad adds a search field in `tabViewSidebarHeader`. While the sidebar is visible, it replaces the Search tab label
  and presents results in the main Chats area without a second search field. The top-bar layout retains the Search tab.
- Activating iPad search with an empty query shows guidance, not all conversations. Selecting a result opens it in Chats,
  removes search focus, and preserves the query. Selecting a sidebar destination exits search.
- `ModelsView` does not currently use `.searchable`; do not claim model search exists.

```swift
NavigationStack {
    List(filteredConversations) { conversation in
        ConversationRow(conversation: conversation)
    }
    .searchable(text: $searchText, prompt: String(localized: "Search conversations..."))
}
```

## Toast Notifications (Preferred, Not Currently Centralized)

There is no current app-wide `ToastManager`/`ToastView` overlay. If a feature introduces centralized transient feedback,
use the following design rather than assuming the sample below already exists.

### Design

- **Position**: Top of the screen, centered horizontally, below the safe area
- **Style**: Rounded capsule with translucent background (`.ultraThinMaterial`) and subtle shadow
- **Content**: SF Symbol icon + short message text (one line max)
- **Animation**: Slide in from top with `.spring()`, auto-dismiss after **3 seconds**
- **Dismiss**: Auto-dismisses; user can also swipe up to dismiss early
- **Stacking**: Only one toast visible at a time — new toasts replace the current one

### When to Use

> **App-Specific** (table below) — Adapt toast scenarios for your project.

| Scenario | Toast |
|---|---|
| Connection test success | ✅ `checkmark.circle` + "Connected successfully" |
| Message copied | ✅ `doc.on.doc` + "Copied to clipboard" |
| Connection test failed | ✅ `xmark.circle` + "Connection failed" (if inline error also shown) |
| Settings saved | ✅ `checkmark.circle` + "Settings saved" |

### When NOT to Use

- Critical errors that need user action → use inline error state
- Data loss confirmations → use `.confirmationDialog()`
- Loading states → use inline `ProgressView`

### Implementation Pattern

```swift
// Toast overlay applied at HomeView level (once, not per screen)
.overlay(alignment: .top) {
    if let toast = toastManager.current {
        ToastView(toast: toast)
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(.top, 8)
    }
}
```

## Keyboard Avoidance (iOS / iPadOS)

**Mandatory rule**: The keyboard must NEVER cover any text input field where the user types. This is a non-negotiable UX requirement.

### Implementation Rules

- Every view with text input must be wrapped in a `ScrollView` or use a layout that adjusts for the keyboard
- SwiftUI's default keyboard avoidance is enabled by default — **do not disable it** with `.ignoresSafeArea(.keyboard)`
- For chat input at the bottom of the screen: the input area must sit above the keyboard when active, pushing content up
- Use `.scrollDismissesKeyboard(.interactively)` on `ScrollView` to allow dismissing the keyboard by dragging down
- On iPadOS with external keyboard: ensure layouts don't break when the software keyboard is hidden

### Chat Input Specific

```swift
// Input area stays above keyboard automatically via safe area
VStack {
    ScrollView {
        // Messages
    }
    .scrollDismissesKeyboard(.interactively)

    ChatInputView() // Anchored to bottom, respects keyboard safe area
}
```

### Form Input Specific

- Forms with multiple fields: wrap in `ScrollView` so the active field scrolls into view
- Use `Form` or `List` containers — they handle keyboard avoidance natively
- After submit, dismiss keyboard explicitly with `FocusState`

### Dismiss Keyboard Rules

- Tapping outside a text field should dismiss the keyboard (use `FocusState` + `.onTapGesture`)
- Sending a message in chat should NOT dismiss the keyboard (user may want to keep typing)
- Submitting a form should dismiss the keyboard
- Swiping down on a `ScrollView` dismisses the keyboard (`.scrollDismissesKeyboard(.interactively)`)

## State Patterns

Every screen must handle all possible data states. Never show a blank screen.

### Loading State

- Use `ProgressView()` centered on screen for initial data load
- For refreshing existing data, prefer inline indicators (e.g., toolbar progress) over full-screen spinners
- Never block interaction with a full-screen opaque loader — use non-blocking indicators when possible
- Streaming responses use an animated typing indicator, not a spinner

### Empty State

- Every list/collection screen must show an empty state when there are no items
- Empty state pattern: **SF Symbol** (large, secondary color) + **title** (headline) + **subtitle** (subheadline, secondary) + **action button** (optional)
- Example: Chats tab with no conversations → `bubble.left.and.bubble.right` icon + "No conversations yet" + "Start a new chat" button
- Use `ContentUnavailableView` (iOS 17+) as the standard empty state component

```swift
ContentUnavailableView {
    Label(String(localized: "No conversations"), systemImage: "bubble.left.and.bubble.right")
} description: {
    Text(String(localized: "Start a new chat to begin"))
} actions: {
    Button(String(localized: "New Chat")) {
        // action
    }
}
```

### Error State

- Show errors inline within the view — avoid blocking `alert()` dialogs for recoverable errors
- Error pattern: SF Symbol (`exclamationmark.triangle`) + error message + "Retry" button
- Use `ContentUnavailableView` for full-screen errors (e.g., failed to load model list)
- For transient errors (network timeout), show a banner or inline message that auto-dismisses or has a manual dismiss
- Connection errors on chat: show inline error below the failed message with a "Retry" option
- Never show raw error codes or technical details to the user — use human-readable localized messages

### No Connection State

- When the server is unreachable, show a clear "No connection" state with a retry action
- Do not silently fail — always inform the user

## Form & Input Patterns

### Text Fields

- Use `TextField` with a clear localized placeholder
- Use `SecureField` for API keys and sensitive data
- Group related fields with `Section` inside `Form` or `List`
- Add `.textContentType()` hint when applicable (`.URL` for server URL)
- Use `.autocorrectionDisabled()` and `.textInputAutocapitalization(.never)` for URLs, API keys, and technical input
- Use `.submitLabel()` to set the keyboard return key (`.done`, `.next`, `.send`)

### Validation

- Validate input inline as the user types or on field exit — not only on submit
- Show validation errors below the field in `.caption` font with destructive color
- Disable "Submit" / "Next" button until required fields are valid
- For server URL: validate format before allowing connection test
- For API key: don't validate format — only test via actual connection

### FocusState

- Use `@FocusState` to manage keyboard focus across multiple fields
- Move focus to the next field on "Next" keyboard button
- Dismiss keyboard on "Done" or successful form submission

## Modals & Sheets

- Use `.sheet()` for modal presentations (new chat, edit settings)
- Prefer `.confirmationDialog()` for contextual destructive actions. Existing Settings and conversation flows also use
  `.alert`; preserve their behavior unless the task includes migrating that presentation.
- Use `.popover()` on iPadOS/macOS for contextual options
- Sheets should have a clear dismiss action (Cancel button or swipe down)
- Sheets should not be full-screen on iPadOS/macOS — use `.presentationDetents()` to control height when appropriate

### Destructive Actions

- **Always confirm** before deleting conversations, clearing data, or resetting settings
- Use `.confirmationDialog()` with a descriptive title and a `.destructive` role button
- Example: "Delete Conversation?" → "This action cannot be undone." → [Delete] [Cancel]
- Never auto-delete without user confirmation

## Scroll Behavior

### Chat Scroll

- Use `ScrollViewReader` with explicit top and bottom sentinels; do not bind live chat position on macOS
- If the user scrolls to read history, detach bottom-follow immediately and show a "Scroll to bottom" floating button
- `ScrollTriggerModifier` owns initial, response-start, coalesced-content, final-layout, and favourite-message positioning
- Never drive automatic chat scrolling from geometry or visibility observers; use semantic revisions and scroll phases
- Preserve the user's position after interaction until a new response starts or the user explicitly returns to the bottom

### List Scroll

- Use `.refreshable {}` for pull-to-refresh on lists that load from the server (models list, conversations list)
- Maintain scroll position when data updates (e.g., new conversation added to list)

## Safe Areas

- **Always respect safe areas** — never place interactive content under the notch, Dynamic Island, or home indicator
- Use `.safeAreaInset()` for floating elements that should respect the safe area (e.g., floating action button)
- The chat input bar uses `.safeAreaInset(edge: .bottom)` to anchor above the safe area and keyboard
- On macOS, respect the title bar area — never overlap content with window controls

## Gestures

- Use standard system gestures — swipe to delete in lists, swipe back for navigation
- Do not override system gestures (edge swipe for back navigation)
- Long press on a message for context menu (copy, retry, delete)
- Use `.contextMenu()` or `.swipeActions()` — never custom gesture recognizers for standard interactions

## Chat UI Patterns

- **Message bubbles**: Rounded rectangles, different alignment/color for user vs assistant
- **Streaming indicator**: A blinking `█` cursor after content begins; a static localized "Thinking..." label appears
  while streaming has started but both answer and reasoning content are empty
- **Input area**: Text field with send button, anchored to bottom with keyboard avoidance
- **Scroll behavior**: Auto-scroll with explicit `ScrollViewReader` targets, allow manual scroll to detach immediately, and
  never bind live scroll position while a response is active
- **Code blocks**: Implemented as horizontally scrolling monospaced text with language/"Code" header, material
  background, and a copy button. Syntax coloring is not currently implemented.
- **Markdown rendering**: Render assistant messages as Markdown (bold, italic, lists, links, code)
- **Timestamps**: Shown outside message surfaces in trailing `.caption2`/tertiary styling; a centered date capsule appears
  only during manual history scrolling
- **Copy message**: Long press or context menu to copy full message text

> For detailed chat UI implementation patterns, see `chat-visual-style.instructions.md`.

---

## App-Specific Sections Summary

The following sections in this document contain project-specific configuration for **OpenClient** and should be adapted when reusing these guidelines in another project:

| Section | What to adapt |
|---|---|
| **Current App Assets** | Accent, legacy chat colors, logo/provider images, and their actual use |
| **App Navigation Structure** | Specific tabs, sidebar sections, navigation hierarchy |
| **App Flow** | Entry point routing, onboarding steps, screen flow |
| **macOS Window** | Window sizes and resizability |
| **Toolbar Patterns** | Per-screen toolbar action table |
| **Toast Scenarios** | App-specific notification scenarios table |

All other sections are **generic Apple design guidelines** reusable across any SwiftUI project targeting iOS 26+ / macOS 26+.
