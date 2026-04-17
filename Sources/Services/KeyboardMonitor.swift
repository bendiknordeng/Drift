import AppKit
import SwiftUI

final class KeyboardMonitor {
    static let shared = KeyboardMonitor()
    private var monitor: Any?
    private weak var appState: AppState?

    func start(appState: AppState) {
        self.appState = appState
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let appState = self.appState else { return event }
            let cmd = event.modifierFlags.contains(.command)
            guard cmd else { return event }

            switch event.keyCode {
            case 53:  // Escape
                DispatchQueue.main.async { Task { await appState.goHome() } }
                return nil
            case 24:  // =/+
                DispatchQueue.main.async {
                    appState.fontScale = min(2.0, appState.fontScale + 0.1)
                }
                return nil
            case 27:  // -
                DispatchQueue.main.async {
                    appState.fontScale = max(0.6, appState.fontScale - 0.1)
                }
                return nil
            case 29:  // 0
                DispatchQueue.main.async { appState.fontScale = 1.0 }
                return nil
            default:
                return event
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
