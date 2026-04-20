<p align="center">
  <img src="Sources/Assets.xcassets/DriftLogo.imageset/drift_logo.png" width="120" alt="Drift Logo" />
</p>

<h1 align="center">Drift</h1>

<p align="center">
  <strong>A fast, keyboard-first PostgreSQL browser for macOS</strong><br/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014+-blue?style=flat-square" />
  <img src="https://img.shields.io/badge/swift-5.9+-orange?style=flat-square" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" />
</p>

---

## Features

- **Native macOS app** — SwiftUI + AppKit, no Electron
- **Cell-level selection** — click, shift-click, cmd-click, drag-select, arrow keys
- **Keyboard-first** — Cmd+P quick open, Cmd+Shift+F global search, Cmd+K AI query, Cmd+Shift+E SQL editor
- **SQL editor** — syntax highlighting, autocomplete, Cmd+Enter to execute
- **Neon integration** — connect to Neon databases directly via API key
- **Connection string support** — paste any `postgres://` URI
- **AI-powered queries** — describe what you want in natural language (Claude API)
- **IDE-style tabs** — preview tabs, double-click to pin, navigation history
- **Column filtering** — per-column ILIKE filters with debounced search
- **Infinite scroll** — lazy loading with automatic pagination
- **Dark theme** — Linear-inspired design with purple accents

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘P` | Quick open (fuzzy table search) |
| `⌘⇧F` | Global value search |
| `⌘K` | AI query (Claude API) |
| `⌘⇧E` | SQL editor |
| `⌘⇧B` | Table browser |
| `⌘N` | New connection |
| `⌘⏎` | Execute SQL |
| `⌘C` | Copy selected cells |
| `⌘Esc` | Go home |
| `⌘[` / `⌘]` | Navigate back/forward |
| `⌘=` / `⌘-` | Zoom in/out |
| `Arrow keys` | Navigate cells |
| `Shift+Arrows` | Extend selection |

## Getting Started

### Requirements
- macOS 14+
- Xcode 15+ (for building)

### Build & Run

```bash
# Clone
git clone https://github.com/bendiknordeng/Drift.git
cd Drift

# Build and run
swift build
swift run Drift

# Or open in Xcode
open Package.swift
```

### Connect to a Database

1. Launch Drift
2. Click **New Connection** or press `⌘N`
3. Enter your PostgreSQL credentials, paste a connection string, or use Neon API key
4. Browse your schemas and tables

## Architecture

```
Sources/
├── DriftApp.swift              # App entry point
├── Theme.swift                 # Design tokens (colors, fonts, spacing)
├── Models/
│   └── Models.swift            # Data models
├── Services/
│   ├── PostgresService.swift   # PostgresNIO connection & queries
│   ├── NeonService.swift       # Neon API integration
│   ├── LLMService.swift        # Claude API for AI queries
│   ├── ConnectionStore.swift   # UserDefaults persistence
│   └── KeyboardMonitor.swift   # Global keyboard shortcuts
├── State/
│   └── AppState.swift          # Observable app state
└── Views/
    ├── MainView.swift          # Main layout + welcome screen
    ├── SidebarView.swift       # Schema tree browser
    ├── DataGridView.swift      # Grid container + filters
    ├── NSDataGridView.swift    # NSTableView-based data grid
    ├── SQLEditorView.swift     # SQL editor pane
    ├── SQLSyntaxEditor.swift   # NSTextView with syntax highlighting
    ├── GlobalSearchView.swift  # ⌘⇧F search overlay
    ├── CommandPalette.swift    # ⌘P quick open
    ├── LLMChatView.swift       # ⌘K AI chat
    ├── ConnectionSheet.swift   # Connection dialog
    ├── SettingsView.swift      # Settings overlay
    └── StatusBarView.swift     # Bottom status bar
```

Built with [PostgresNIO](https://github.com/vapor/postgres-nio) for the PostgreSQL wire protocol.

## License

MIT — see [LICENSE](LICENSE) for details.
