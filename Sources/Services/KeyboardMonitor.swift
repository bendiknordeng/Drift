import AppKit
import SwiftUI

@MainActor
final class KeyboardMonitor {
    static let shared = KeyboardMonitor()
    private var monitor: Any?
    private weak var appState: AppState?
    private weak var browserGridTableView: DriftCellTableView?

    func registerBrowserGrid(_ tableView: DriftCellTableView) {
        browserGridTableView = tableView
    }

    func start(appState: AppState) {
        self.appState = appState
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let appState = self.appState else { return event }

            if self.isGoHomeShortcut(event) {
                DispatchQueue.main.async { Task { await appState.goHome() } }
                return nil
            }

            if self.routeBrowserGridKey(event, appState: appState) {
                return nil
            }

            if self.routeBrowserSidebarKey(event, appState: appState) {
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
}
