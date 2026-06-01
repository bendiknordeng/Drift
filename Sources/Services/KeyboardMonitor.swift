import AppKit
import SwiftUI

@MainActor
final class KeyboardMonitor {
    static let shared = KeyboardMonitor()
    private var monitor: Any?
    private weak var appState: AppState?
    private weak var browserGridTableView: DriftCellTableView?
    private weak var globalSearchGridTableView: DriftCellTableView?
    private weak var sqlEditorTextView: SQLTextView?

    func registerBrowserGrid(_ tableView: DriftCellTableView) {
        browserGridTableView = tableView
    }

    func registerGlobalSearchGrid(_ tableView: DriftCellTableView) {
        globalSearchGridTableView = tableView
    }

    func registerSQLEditor(_ textView: SQLTextView) {
        sqlEditorTextView = textView
    }

    func start(appState: AppState) {
        self.appState = appState
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let appState = self.appState else { return event }

            if self.isCloseSettingsShortcut(event, appState: appState) {
                DispatchQueue.main.async {
                    appState.showSettings = false
                }
                return nil
            }

            if self.isGoHomeShortcut(event) {
                DispatchQueue.main.async { Task { await appState.goHome() } }
                return nil
            }

            if self.routeHomeShortcutKey(event, appState: appState) {
                return nil
            }

            if self.routeGlobalSearchGridKey(event, appState: appState) {
                return nil
            }

            if self.routeBrowserGridKey(event, appState: appState) {
                return nil
            }

            if self.routeBrowserSidebarKey(event, appState: appState) {
                return nil
            }

            if self.routeSQLSnippetShortcut(event, appState: appState) {
                return nil
            }

            if self.routeSQLEditorTyping(event, appState: appState) {
                return nil
            }

            if self.isZoomInShortcut(event) {
                DispatchQueue.main.async {
                    appState.fontScale = min(2.0, appState.fontScale + 0.1)
                }
                return nil
            }

            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard modifiers == [.command] else { return event }

            switch event.keyCode {
            case 15:  // R
                DispatchQueue.main.async {
                    Task { await appState.refreshCurrentContext() }
                }
                return nil
            case 27:  // -
                DispatchQueue.main.async {
                    appState.fontScale = max(0.6, appState.fontScale - 0.1)
                }
                return nil
            default:
                if self.isZoomOutShortcut(event) {
                    DispatchQueue.main.async {
                        appState.fontScale = max(0.6, appState.fontScale - 0.1)
                    }
                    return nil
                }
                guard event.characters == "0" else { return event }
                DispatchQueue.main.async {
                    appState.fontScale = 1.0
                }
                return nil
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func isGoHomeShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return modifiers == [.command] && (event.keyCode == 4 || event.keyCode == 53)
    }

    private func isCloseSettingsShortcut(_ event: NSEvent, appState: AppState) -> Bool {
        guard appState.showSettings else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return modifiers.isEmpty && event.keyCode == 53
    }

    private func isZoomInShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == [.command] || modifiers == [.command, .shift] else { return false }
        guard let characters = event.characters else { return false }
        return characters == "+" || characters == "="
    }

    private func isZoomOutShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == [.command] else { return false }
        return event.characters == "-"
    }

    private func routeHomeShortcutKey(_ event: NSEvent, appState: AppState) -> Bool {
        guard !appState.isConnected,
              !appState.showConnectionSheet,
              !appState.showSettings,
              !appState.showCommandPalette,
              !appState.showGlobalSearch,
              !appState.showLLMChat else {
            return false
        }

        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == [.command],
              let characters = event.charactersIgnoringModifiers,
              let digit = Int(characters),
              (1...9).contains(digit) else {
            return false
        }

        let shortcuts = appState.homeShortcutConnections()
        guard digit <= shortcuts.count else { return false }

        let connection = shortcuts[digit - 1]
        DispatchQueue.main.async {
            Task { await appState.connect(to: connection) }
        }
        return true
    }

    private func routeBrowserGridKey(_ event: NSEvent, appState: AppState) -> Bool {
        guard appState.isConnected,
              appState.activeTab == .browser,
              appState.selectedTable != nil,
              !appState.showCommandPalette,
              !appState.showGlobalSearch,
              !appState.showLLMChat,
              !appState.showSettings,
              !appState.showConnectionSheet,
              let tableView = browserGridTableView,
              let window = tableView.window else {
            return false
        }

        let firstResponder = window.firstResponder
        if firstResponder is NSTextView {
            return false
        }

        switch event.keyCode {
        case 123, 124, 125, 126:
            let isCommandArrow = event.modifierFlags.contains(.command)
            let shouldRoute = isCommandArrow || firstResponder !== tableView
            guard shouldRoute else { return false }
            window.makeFirstResponder(tableView)
            tableView.keyDown(with: event)
            return true

        case 0:  // A
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard modifiers == [.command] else { return false }
            window.makeFirstResponder(tableView)
            tableView.selectAll(nil)
            return true

        default:
            return false
        }
    }

    private func routeGlobalSearchGridKey(_ event: NSEvent, appState: AppState) -> Bool {
        guard appState.showGlobalSearch,
              let tableView = globalSearchGridTableView,
              let window = tableView.window else {
            return false
        }

        if window.firstResponder is NSTextView {
            return false
        }

        switch event.keyCode {
        case 123, 124, 125, 126:
            window.makeFirstResponder(tableView)
            tableView.keyDown(with: event)
            return true
        case 0:  // A
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard modifiers == [.command] else { return false }
            window.makeFirstResponder(tableView)
            tableView.selectAll(nil)
            return true
        default:
            return false
        }
    }

    private func routeBrowserSidebarKey(_ event: NSEvent, appState: AppState) -> Bool {
        guard appState.isConnected,
              appState.activeTab == .browser,
              appState.selectedTable == nil,
              !appState.showCommandPalette,
              !appState.showGlobalSearch,
              !appState.showLLMChat,
              !appState.showSettings,
              !appState.showConnectionSheet else {
            return false
        }

        if NSApp.keyWindow?.firstResponder is NSTextView {
            return false
        }

        switch event.keyCode {
        case 125: // down
            DispatchQueue.main.async {
                appState.requestSidebarNavigation(direction: 1)
            }
            return true
        case 126: // up
            DispatchQueue.main.async {
                appState.requestSidebarNavigation(direction: -1)
            }
            return true
        default:
            return false
        }
    }

    private func routeSQLEditorTyping(_ event: NSEvent, appState: AppState) -> Bool {
        guard appState.isConnected,
              appState.activeTab == .sql,
              !appState.showCommandPalette,
              !appState.showGlobalSearch,
              !appState.showLLMChat,
              !appState.showSettings,
              !appState.showConnectionSheet,
              let textView = sqlEditorTextView,
              let window = textView.window else {
            return false
        }

        if window.firstResponder === textView || window.firstResponder is NSTextView {
            return false
        }

        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers.isEmpty || modifiers == [.shift] else { return false }
        guard shouldRouteToSQLEditor(event) else { return false }

        window.makeFirstResponder(textView)
        return false
    }

    private func routeSQLSnippetShortcut(_ event: NSEvent, appState: AppState) -> Bool {
        guard appState.isConnected,
              appState.activeTab == .sql,
              !appState.showCommandPalette,
              !appState.showGlobalSearch,
              !appState.showLLMChat,
              !appState.showSettings,
              !appState.showConnectionSheet,
              let textView = sqlEditorTextView,
              let window = textView.window else {
            return false
        }

        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == [.command],
              let characters = event.charactersIgnoringModifiers,
              let digit = Int(characters),
              let snippet = sqlSnippet(for: digit) else {
            return false
        }

        window.makeFirstResponder(textView)
        textView.insertSQLSnippet(snippet)
        return true
    }

    private func sqlSnippet(for digit: Int) -> String? {
        switch digit {
        case 1: return "SELECT "
        case 2: return "FROM "
        case 3: return "WHERE "
        case 4: return "JOIN "
        case 5: return "GROUP BY "
        case 6: return "LIMIT "
        default: return nil
        }
    }

    private func shouldRouteToSQLEditor(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 48, 51, 53, 115, 116, 119, 121, 123, 124, 125, 126:
            return event.keyCode == 51
        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }
    }
}
