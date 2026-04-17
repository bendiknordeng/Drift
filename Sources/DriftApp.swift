import SwiftUI
import AppKit

@main
struct DriftApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            GeometryReader { geo in
                MainView()
                    .environmentObject(appState)
                    .frame(width: geo.size.width / appState.fontScale,
                           height: geo.size.height / appState.fontScale)
                    .scaleEffect(appState.fontScale, anchor: .topLeading)
            }
            .frame(minWidth: 900, minHeight: 600)
            .background(Theme.bg)
            .preferredColorScheme(appState.appearance.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Toggle Sidebar") {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandGroup(replacing: .appVisibility) {
                Button("Go Home") {
                    Task { await appState.goHome() }
                }
                .keyboardShortcut("h", modifiers: .command)

                Divider()

                Button("Hide Drift") {
                    NSApp.hide(nil)
                }

                Button("Hide Others") {
                    NSApp.hideOtherApplications(nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .option])

                Button("Show All") {
                    NSApp.unhideAllApplications(nil)
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Connection...") {
                    appState.showConnectionSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Quick Open") {
                    appState.showCommandPalette.toggle()
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("Search All Values") {
                    appState.showGlobalSearch.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("AI Query") {
                    appState.showLLMChat.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("SQL Editor") {
                    appState.activeTab = .sql
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Table Browser") {
                    appState.activeTab = .browser
                }
                .keyboardShortcut("b", modifiers: .command)

                Divider()

                Button("Execute SQL") {
                    if appState.activeTab == .sql {
                        Task { await appState.executeSQL() }
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Refresh") {
                    Task { await appState.refreshCurrentContext() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Settings") {
                    appState.showSettings.toggle()
                }
                .keyboardShortcut(",", modifiers: .command)

                Divider()

                Button("Navigate Back") {
                    Task { await appState.navigateBack() }
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Button("Navigate Forward") {
                    Task { await appState.navigateForward() }
                }

            }
        }

        // Settings handled as in-app overlay via Cmd+,
    }
}
