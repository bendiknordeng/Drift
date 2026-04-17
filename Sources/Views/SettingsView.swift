import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var llmKey = ""
    @State private var neonKey = ""
    @State private var llmModel = "claude-sonnet-4-20250514"
    @State private var selectedTab = 0
    @FocusState private var viewFocused: Bool

    private let tabs = ["Appearance", "Integrations", "Shortcuts", "About"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(.body, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Button { state.showSettings = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(.caption).weight(.medium))
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(Theme.surfaceHover)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            // Tab bar
            HStack(spacing: 2) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { idx, label in
                    Button { selectedTab = idx } label: {
                        Text(label)
                            .font(.system(.caption, weight: .medium))
                            .foregroundColor(selectedTab == idx ? Theme.text : Theme.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedTab == idx ? Theme.surfaceHover : Color.clear)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            Rectangle().fill(Theme.border).frame(height: 1)

            // Content
            Group {
                switch selectedTab {
                case 0: appearanceTab
                case 1: integrationsTab
                case 2: shortcutsTab
                default: aboutTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 420, height: 440)
        .background(Theme.overlay)
        .cornerRadius(Theme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .focused($viewFocused)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            state.showSettings = false
            return .handled
        }
        .onKeyPress(.escape, phases: .down) { press in
            guard press.modifiers.contains(.command), state.isConnected else { return .ignored }
            Task { await state.goHome() }
            return .handled
        }
        .onKeyPress(.tab) {
            selectedTab = (selectedTab + 1) % tabs.count
            return .handled
        }
        .onAppear {
            viewFocused = true
            llmKey = state.store.llmAPIKey
            neonKey = state.store.neonAPIKey
            llmModel = state.llm.model
        }
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.caption)
                        .foregroundColor(Theme.accent)
                    Text("Appearance")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundColor(Theme.text)
                }

                Picker("Theme", selection: $state.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Text("Drift starts in dark mode by default. Your selection is saved and applied across the app immediately.")
                    .font(.system(.caption))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Theme.surface)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Integrations

    private var integrationsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Claude
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.caption).foregroundColor(Theme.accent)
                    Text("Claude API")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    statusBadge(!llmKey.isEmpty)
                }

                fieldRow("API Key", secure: $llmKey, placeholder: "sk-ant-...") {
                    state.updateLLMAPIKey($0)
                }

                HStack(spacing: 6) {
                    Text("Model")
                        .font(.system(.caption2))
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 48, alignment: .trailing)

                    HStack(spacing: 0) {
                        modelButton("Sonnet", tag: "claude-sonnet-4-20250514")
                        modelButton("Haiku", tag: "claude-haiku-4-5-20251001")
                        modelButton("Opus", tag: "claude-opus-4-6")
                    }
                    .background(Theme.bg)
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border, lineWidth: 1))
                }
            }
            .padding(12)
            .background(Theme.surface)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))

            // Neon
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image("NeonLogo").resizable().frame(width: 14, height: 14)
                    Text("Neon")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    statusBadge(!neonKey.isEmpty)
                }

                fieldRow("API Key", secure: $neonKey, placeholder: "neon_api_key_...") {
                    state.updateNeonAPIKey($0)
                }
            }
            .padding(12)
            .background(Theme.surface)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))

            Spacer()
        }
        .padding(20)
    }

    private func modelButton(_ label: String, tag: String) -> some View {
        Button {
            llmModel = tag
            state.llm.model = tag
        } label: {
            Text(label)
                .font(.system(.caption2, weight: llmModel == tag ? .semibold : .regular))
                .foregroundColor(llmModel == tag ? Theme.text : Theme.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(llmModel == tag ? Theme.surfaceHover : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func fieldRow(_ label: String, secure: Binding<String>, placeholder: String, onChange: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(.caption2))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 48, alignment: .trailing)
            SecureField(placeholder, text: secure)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.bg)
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border, lineWidth: 1))
                .onChange(of: secure.wrappedValue) { _, v in onChange(v) }
        }
    }

    private func statusBadge(_ active: Bool) -> some View {
        HStack(spacing: 4) {
            Circle().fill(active ? Theme.success : Theme.textTertiary).frame(width: 5, height: 5)
            Text(active ? "Active" : "Not set")
                .font(.system(.caption2))
                .foregroundColor(active ? Theme.success : Theme.textTertiary)
        }
    }

    // MARK: - Shortcuts

    private var shortcutsTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { idx, item in
                    HStack {
                        Text(item.label)
                            .font(.system(.caption))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        Kbd(item.shortcut)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 5)

                    if idx < shortcuts.count - 1 {
                        Rectangle().fill(Theme.borderSubtle).frame(height: 1).padding(.horizontal, 20)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var shortcuts: [(label: String, shortcut: String)] {
        [
            ("Go Home", "⌘H"),
            ("Open Home Connection", "⌘1-9"),
            ("Quick Open", "⌘P"),
            ("Search Values", "⌘⇧F"),
            ("AI Query", "⌘K"),
            ("SQL Editor", "⌘E"),
            ("SQL Snippets", "⌘1-6"),
            ("Table Browser", "⌘B"),
            ("Execute SQL", "⌘⏎"),
            ("Refresh", "⌘R"),
            ("New Connection", "⌘N"),
            ("Navigate Back", "⌘←"),
            ("Navigate Forward", "⌘→"),
            ("Settings", "⌘,"),
        ]
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Spacer()
            VStack(spacing: 3) {
                Text("Drift")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.text)
                Text("v0.1.0")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
            }
            Text("PostgreSQL Browser for macOS")
                .font(.system(.caption))
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
    }
}

// MARK: - Kbd Component (shadcn-inspired)

struct Kbd: View {
    enum Variant {
        case standard
        case primary
    }

    let keys: [String]
    let variant: Variant

    init(_ shortcut: String, variant: Variant = .standard) {
        var result: [String] = []
        for char in shortcut {
            result.append(String(char))
        }
        self.keys = result
        self.variant = variant
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundColor(textColor)
                    .frame(minWidth: 14, minHeight: 14)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var textColor: Color {
        switch variant {
        case .standard:
            return Theme.textSecondary
        case .primary:
            return Color.white.opacity(0.92)
        }
    }

    private var backgroundColor: Color {
        switch variant {
        case .standard:
            return Theme.surface
        case .primary:
            return Color.white.opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch variant {
        case .standard:
            return Theme.border
        case .primary:
            return Color.white.opacity(0.18)
        }
    }
}
