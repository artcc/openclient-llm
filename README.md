<p align="center">
  <a href="https://www.arturocarreterocalvo.com/openclient-llm/">
    <img src="docs/assets/og-image.png" alt="OpenClient — Native Apple Client for OpenAI-compatible APIs" width="100%" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-AGPL%20v3.0-blue?style=flat-square" alt="License" />
  <img src="https://img.shields.io/badge/Platform-iOS%2026+%20|%20iPadOS%2026+%20|%20macOS%2026+-blue?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-6+-orange?style=flat-square&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/Version-1.6.45-brightgreen?style=flat-square" alt="Version 1.6.45" />
</p>

OpenClient connects directly to the AI server you configure, without an OpenClient-hosted proxy or subscription.
Requests may still reach providers configured behind your server, and the optional in-app feedback screen uses Votice.

It works with [LiteLLM](https://github.com/BerriAI/litellm), [Ollama](https://ollama.com), and OpenAI-compatible
servers that provide the endpoints used by your selected features; point the app at your URL and use the models it exposes.

<p align="center">
  <a href="https://github.com/artcc/openclient-llm/releases"><strong>macOS Releases</strong></a>
  &nbsp;&middot;&nbsp;
  <a href="https://www.arturocarreterocalvo.com/openclient-llm/"><strong>Website</strong></a>
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/id6761379499">
    <img src="assets/app_store_black.png" alt="Download on the App Store" width="156" height="52" />
  </a>
  &nbsp;&nbsp;
  <a href="https://testflight.apple.com/join/MDxfUnGc">
    <img src="assets/testflight_badge_black.png" alt="Available on TestFlight" width="156" height="52" />
  </a>
</p>

## Screenshots

<p align="center">
  <img src="assets/iPhone/1.png" width="185" alt="Models" />&nbsp;&nbsp;
  <img src="assets/iPhone/2.png" width="185" alt="New Chat" />&nbsp;&nbsp;
  <img src="assets/iPhone/3.png" width="185" alt="Chat" />&nbsp;&nbsp;
  <img src="assets/iPhone/4.png" width="185" alt="Chats" />
</p>

## Highlights

| | |
|---|---|
| **Your server** | Connect to LiteLLM, Ollama, or another server that implements the OpenAI-compatible endpoints you use. |
| **Rich conversations** | Stream Markdown, attach images and PDFs, use speech features, and generate images with compatible models. |
| **Tools and agents** | Use server-configured web search, function calling, and MCP tools exposed through LiteLLM. |
| **Apple ecosystem** | Sync with iCloud and use Share Sheet, Shortcuts, widgets, Control Center, and the macOS menu bar companion. |
| **Open source** | Review, modify, and contribute to the complete project under the GNU AGPL v3.0. |

## Features

**Chat**
- Real-time streaming responses with Markdown and code block rendering
- Collapsible Thinking block for reasoning models (DeepSeek, o1, Gemini Thinking, and more)
- Attach photos, camera shots, and PDF documents for multimodal conversations
- Drag and drop text, images, and files from any app directly into the chat (Split View, Stage Manager, Finder on macOS)
- Dictate messages with Speech-to-Text; have responses read aloud with Text-to-Speech
- Generate images with dedicated LiteLLM image models and receive images returned in chat-completion streams
- Web search powered by your server's configured provider (Brave, Firecrawl, and more)
- Agentic tool-calling loop for models that support function calling
- MCP (Model Context Protocol) tools — connect to external services (GitHub, filesystems, databases, and more) through MCP servers configured on your LiteLLM backend; discover, enable, and execute them from the chat input bar
- Favourite any message to bookmark it and jump back instantly
- Custom system prompt and model parameters (temperature, max tokens, top-p) per conversation

**Conversations**
- Full conversation history with search, pins, and tags
- Branch from any message to explore alternative responses; edit and regenerate
- Media & Files gallery: browse all attached images and documents in one place
- Share content from any app (Safari, Telegram, Photos, Files…) directly into a new conversation via the system Share sheet
- Deep-link into the app with `openclient://chat?text=…`, `openclient://chat?url=…`, or `openclient://conversation?id=…` for third-party automation
- Apple Shortcuts integration: "New Chat", "Search Chats", and "Send File to Chat" actions available in the Shortcuts app and via Siri
- Control Center toggle: add a "New Chat" button for instant one-tap access on iPhone, iPad, and Mac
- Native iOS, iPadOS, and macOS widgets: New Chat and Search (small); Quick Actions and Continue Chat (medium); and Recent, Pinned, or Tagged Conversations (medium/large)
- Optional iCloud sync for conversations, attachments, personal context, memory, and custom prompt templates across supported iPhone, iPad, and Mac devices
- Export individual conversations or full JSON backups, and restore backups on another device ([format specification](specs/conversation-backup-format.instructions.md))
- Private Chat: start a session-only chat whose messages and attachments are discarded when you close it; personal memory is neither read nor changed
- Token usage per message and estimated conversation cost when the backend returns usage and pricing metadata

**Models**
- Browse available models with capability badges supplied by `/model/info`, plus best-effort Ollama capability detection
- Model detail sheet showing available context, pricing, provider, mode, and capability metadata
- Voice selector for Text-to-Speech models
- Switch models per conversation

**Personalization**
- Prompt template library: save and reuse system prompts for any workflow
- User profile: set your name and context so every model addresses you personally
- Memory: save facts and preferences (manually or let the model save them automatically); injected into every conversation's system prompt and synced when iCloud synchronization is enabled
- Localized in English, Spanish, French, Italian, German, Portuguese (Portugal), Japanese, Dutch, Greek, and Swedish

**macOS**
- Menu bar companion for instant access without opening the main window
- Native desktop and Notification Center widgets with conversation shortcuts, pinned and tagged chats, search, and New Chat

**macOS:** Download the latest signed and notarized `.dmg` directly from the [Releases](https://github.com/artcc/openclient-llm/releases) page.

## Technologies

| Technology | Purpose |
|-----------|---------|
| Swift 6+ | Language |
| SwiftUI | UI Framework |
| Liquid Glass | Design language (iOS 26+) |
| async/await | Concurrency |
| URLSession + SSE | Networking & streaming |
| Keychain | Secure storage |
| SwiftLintPlugins | Build-time code linting |
| ConfettiSwiftUI | Tip-jar celebration effect |
| SF Symbols | Iconography |
| AppIntents | Apple Shortcuts, Siri & Control Center integration |
| WidgetKit | Native iOS, iPadOS, and macOS widgets plus a New Chat system control |
| Votice | In-app feedback & feature requests |

This project was developed entirely with Xcode, Visual Studio Code and GitHub Copilot (with Claude Opus / Sonnet 4.6).

## Architecture

The project follows **MVVM + UseCase + Repository + Manager** with Swift strict concurrency and `async/await`. Code is organized by feature under `Shared/`, shared across iOS and macOS targets. Platform-specific UI lives in each target's own folder.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full project tree and layer responsibilities.

## Usage

1. **Clone** the repository:
   ```bash
   git clone https://github.com/ArtCC/openclient-llm.git
   cd openclient-llm
   ```
2. **Create** the required local secrets configuration. Empty placeholders are sufficient to build; real credentials
   are required for the in-app Votice feedback screen:
   ```bash
   cat > Secrets.xcconfig <<'EOF'
   VOTICE_API_KEY =
   VOTICE_API_SECRET =
   VOTICE_APP_ID =
   EOF
   ```
   `Secrets.xcconfig` is gitignored. Xcode Cloud creates it through `ci_scripts/ci_post_clone.sh`.
3. **Open** in Xcode:
   ```bash
   open openclient-llm.xcodeproj
   ```
4. **Configure** your server URL in the app settings:
   - **LiteLLM**: `http://your-server:4000`
   - **Ollama** (direct): `http://your-server:11434/v1`
   OpenClient appends API paths to this value without adding or removing `/v1`: LiteLLM uses paths such as
   `/models` and `/chat/completions`, while direct Ollama requires its `/v1` OpenAI-compatible base.
   If your server requires authentication, enter its API key in the app; OpenClient stores it in Keychain and sends it as
   a Bearer token. This server credential is separate from the Votice values in `Secrets.xcconfig`.
5. **Run** with the `openclient-llm` scheme for iOS/iPadOS or `openclient-llm-macOS` for macOS, selecting the corresponding
   device, simulator, or Mac destination.

### Requirements

- Xcode 26+
- iOS 26+ / macOS 26+
- A running [LiteLLM](https://docs.litellm.ai/) server — recommended backend; proxies [Ollama](https://ollama.com) and cloud providers (OpenAI, Anthropic, Google…) under a single endpoint. See [LiteLLM.md](LiteLLM.md).
- **Or** a running [Ollama](https://ollama.com) instance directly (OpenAI-compatible `/v1` endpoint). See [Ollama.md](Ollama.md). Note: using Ollama through LiteLLM is preferred as it unlocks multi-provider support, virtual keys, and cost tracking.
- **Or** another OpenAI-compatible server that implements `GET /models` and `POST /chat/completions`; endpoints for
  optional features are required only when those features are used.

### Self-hosting guides

OpenClient works with servers that implement the OpenAI-compatible endpoints used by the selected features. Basic chat
requires model listing and chat completions; LiteLLM-only enrichment and search are optional. The two common setups are:

- **Ollama only** — run open-source models locally on your own hardware.
- **LiteLLM + Ollama** — add a proxy layer to combine local models with cloud providers (OpenAI, Anthropic, Google…) under a single endpoint.

The guides below cover Docker Compose configurations, reference `.env` files, and common operational commands:

- [Ollama.md](Ollama.md) — Run Ollama with Docker (CPU and NVIDIA GPU)
- [LiteLLM.md](LiteLLM.md) — Run LiteLLM with Docker (Postgres, local + cloud models)

## License

This project is licensed under the [GNU Affero General Public License v3.0](LICENSE).

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to report issues, propose features, and submit pull requests.

## Feedback

To suggest features or report bugs from within the app, go to **Settings** and use the built-in feedback option powered by [Votice](https://github.com/ArtCC/votice-sdk), another open source project by the same author.

## Author

**Arturo Carretero Calvo**

- [GitHub Profile](https://github.com/ArtCC)

<p align="center">
  <strong>Your AI. Your server. Your rules.</strong>
</p>
