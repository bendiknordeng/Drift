# Drift - PostgreSQL Browser for macOS

## Build & Run
```bash
swift build          # Build the project
swift run Drift      # Run the app
```

Open `Package.swift` in Xcode for IDE development.

## Architecture
- **SwiftUI** macOS app targeting macOS 14+
- **PostgresNIO** for PostgreSQL connectivity
- Linear-inspired dark theme with purple accents

## Project Structure
- `Sources/DriftApp.swift` - App entry point, window scenes, keyboard commands
- `Sources/Theme.swift` - Colors, fonts, dimensions (Linear-inspired design tokens)
- `Sources/Models/` - Data models (connections, schemas, query results, Neon types)
- `Sources/Services/` - PostgresService, NeonService, LLMService, ConnectionStore
- `Sources/State/AppState.swift` - Observable app state with all actions
- `Sources/Views/` - All SwiftUI views

## Key Shortcuts
- `Cmd+N` - New connection
- `Cmd+P` - Quick open (table search)
- `Cmd+Shift+F` - Global value search
- `Cmd+K` - AI query (Claude API)
- `Cmd+Shift+E` - SQL editor
- `Cmd+Shift+B` - Table browser
- `Cmd+Enter` - Execute SQL
