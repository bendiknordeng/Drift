import SwiftUI

struct MainView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            if state.isConnected {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 200, ideal: Theme.sidebarWidth, max: 350)
                } detail: {
                    VStack(spacing: 0) {
                        modeBar
                        Rectangle().fill(Theme.border).frame(height: 1)

                        if !state.openTabs.isEmpty && state.activeTab == .browser {
                            tableTabs
                            Rectangle().fill(Theme.borderSubtle).frame(height: 1)
                        }

                        switch state.activeTab {
                        case .browser:
                            if state.isLoadingSchemas && state.schemas.isEmpty {
                                browserLoadingState
                            } else if state.selectedTable != nil {
                                DataGridView()
                            } else {
                                emptyState("Select a table from the sidebar", icon: "tablecells")
                            }
                        case .sql:
                            SQLEditorView()
                        }

                        StatusBarView()
                    }
                    .background(Theme.bg)
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                WelcomeView()
            }

            // Overlays
            if state.showCommandPalette {
                overlayBackground
                CommandPalette()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if state.showGlobalSearch {
                overlayBackground
                GlobalSearchView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if state.showLLMChat {
                overlayBackground
                LLMChatView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if state.showSettings {
                overlayBackground
                SettingsView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: state.showCommandPalette)
        .animation(.easeOut(duration: 0.15), value: state.showGlobalSearch)
        .animation(.easeOut(duration: 0.15), value: state.showLLMChat)
        .animation(.easeOut(duration: 0.15), value: state.showSettings)
        .onKeyPress(.escape, phases: .down) { press in
            guard press.modifiers.contains(.command), state.isConnected else { return .ignored }
            Task { await state.goHome() }
            return .handled
        }
        .onAppear {
            KeyboardMonitor.shared.start(appState: state)
        }
        .sheet(isPresented: $state.showConnectionSheet) {
            ConnectionSheet()
                .environmentObject(state)
        }
        .alert("Error", isPresented: .init(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    // MARK: - Mode Bar (Browser / SQL)

    private var modeBar: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 12)
            ForEach(ContentTab.allCases, id: \.self) { tab in
                Button {
                    state.activeTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.system(.caption, weight: .medium))
                            .foregroundColor(state.activeTab == tab ? Theme.text : Theme.textTertiary)
                        if let shortcut = modeBarShortcut(for: tab) {
                            Kbd(shortcut)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .overlay(
                    Rectangle()
                        .frame(height: 1.5)
                        .foregroundColor(state.activeTab == tab ? Theme.accent : Color.clear),
                    alignment: .bottom
                )
            }

            Spacer()

            // Back/Forward
            if state.navigationHistory.count > 1 {
                HStack(spacing: 2) {
                    Button { Task { await state.navigateBack() } } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(.caption2).weight(.medium))
                            .foregroundColor(state.historyIndex > 0 ? Theme.textSecondary : Theme.textTertiary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(state.historyIndex <= 0)

                    Button { Task { await state.navigateForward() } } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(.caption2).weight(.medium))
                            .foregroundColor(state.historyIndex < state.navigationHistory.count - 1 ? Theme.textSecondary : Theme.textTertiary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(state.historyIndex >= state.navigationHistory.count - 1)
                }
                .padding(.trailing, 8)
            }

            if let conn = state.activeConnection {
                HStack(spacing: 5) {
                    Circle().fill(Theme.success).frame(width: 5, height: 5)
                    Text(conn.displayName)
                        .font(.system(.caption2))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.trailing, 12)
            }
        }
        .padding(.vertical, 2)
        .background(Theme.bg)
    }

    private func modeBarShortcut(for tab: ContentTab) -> String? {
        switch tab {
        case .browser:
            return "⌘⇧B"
        case .sql:
            return "⌘⇧E"
        }
    }

    // MARK: - Table Tabs

    private var tableTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(state.openTabs) { tab in
                    let isActive = state.selectedTable == tab.ref
                    HStack(spacing: 5) {
                        if tab.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 7))
                                .foregroundColor(Theme.textTertiary)
                        }
                        Text(tab.ref.table)
                            .font(.system(.caption2, design: .monospaced))
                            .italic(!tab.isPinned)
                            .foregroundColor(
                                !tab.isPinned ? Theme.textTertiary :
                                (isActive ? Theme.text : Theme.textSecondary)
                            )
                            .lineLimit(1)

                        Button {
                            state.closeTab(tab.ref)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .opacity(isActive ? 1 : 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isActive ? Theme.surface : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await state.selectTable(tab.ref) }
                    }
                    .onTapGesture(count: 2) {
                        state.pinTab(tab.ref)
                    }
                    .overlay(
                        Rectangle()
                            .frame(width: 1)
                            .foregroundColor(Theme.borderSubtle),
                        alignment: .trailing
                    )
                }
                Spacer()
            }
        }
        .frame(height: 28)
        .background(Theme.bg)
    }

    private var overlayBackground: some View {
        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .onTapGesture {
                state.showCommandPalette = false
                state.showGlobalSearch = false
                state.showLLMChat = false
                state.showSettings = false
            }
    }

    private func emptyState(_ message: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(Theme.textTertiary)
            Text(message)
                .font(.body)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private var browserLoadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(0.9)
                .tint(Theme.accent)
            Text("Loading schema…")
                .font(.system(.body, weight: .medium))
                .foregroundColor(Theme.text)
            Text("Fetching tables and columns for this connection")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

// MARK: - Welcome View (no connection)

struct WelcomeView: View {
    private enum NeonBranchSortKey: Equatable {
        case name
        case created
        case updated
    }

    private struct NeonBranchEntry: Identifiable {
        let project: NeonProject
        let branch: NeonBranch
        let createdDate: Date?
        let updatedDate: Date?
        let createdLabel: String
        let updatedLabel: String

        var id: String { "\(project.id)/\(branch.id)" }
    }

    private struct NeonProjectSection: Identifiable {
        let project: NeonProject
        let branches: [NeonBranchEntry]

        var id: String { project.id }
    }

    @EnvironmentObject var state: AppState
    @State private var neonSearch = ""
    @State private var neonSelectedIndex = -1
    @State private var neonBranchSort: NeonBranchSortKey = .name
    @State private var neonBranchSortDescending = false
    @State private var neonSections: [NeonProjectSection] = []
    @State private var allNeonBranches: [NeonBranchEntry] = []
    @FocusState private var viewFocused: Bool
    @FocusState private var neonSearchFocused: Bool
    private let neonDateFormatter = ISO8601DateFormatter()
    private let homeSearchActivationCharacters =
        CharacterSet.letters
        .union(.decimalDigits)
        .union(.punctuationCharacters)
        .union(.symbols)
        .union(CharacterSet(charactersIn: " "))
    private let welcomeSidebarContentWidth: CGFloat = 340
    private let welcomeSidebarWidth: CGFloat = 392
    private let neonBranchNameColumnWidth: CGFloat = 640
    private let neonBranchDateColumnWidth: CGFloat = 118

    private var neonTableMinWidth: CGFloat {
        32 + 16 + 10 + neonBranchNameColumnWidth + 10 + neonBranchDateColumnWidth + 10 + neonBranchDateColumnWidth + 52
    }

    private var highlightedNeonBranch: NeonBranchEntry? {
        guard neonSelectedIndex >= 0, neonSelectedIndex < allNeonBranches.count else { return nil }
        return allNeonBranches[neonSelectedIndex]
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: New + Recent
            leftPanel

            // Divider
            if state.neon.isConfigured {
                Rectangle().fill(Theme.border).frame(width: 1)
                // Right: Neon databases
                rightPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .focusable()
        .focused($viewFocused)
        .focusEffectDisabled()
        .onAppear {
            viewFocused = true
            rebuildNeonSections()
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789"), phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            let shortcuts = shortcutConnections
            if let digit = Int(String(press.characters)), digit >= 1, digit <= shortcuts.count {
                let conn = shortcuts[digit - 1]
                Task { await state.connect(to: conn) }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: homeSearchActivationCharacters, phases: .down) { press in
            routeTypedCharacterToNeonSearch(press)
        }
        .onKeyPress(.downArrow) {
            if !allNeonBranches.isEmpty { neonSelectedIndex = min(neonSelectedIndex + 1, allNeonBranches.count - 1) }
            return .handled
        }
        .onKeyPress(.upArrow) {
            neonSelectedIndex = max(-1, neonSelectedIndex - 1)
            return .handled
        }
        .onKeyPress(.return) {
            if let item = highlightedNeonBranch {
                Task { await state.connectToNeonBranch(project: item.project, branch: item.branch) }
                return .handled
            }
            return .ignored
        }
        .onChange(of: neonSearch) { _, _ in
            neonSelectedIndex = -1
            rebuildNeonSections()
        }
        .onChange(of: neonBranchSort) { _, _ in rebuildNeonSections() }
        .onChange(of: neonBranchSortDescending) { _, _ in rebuildNeonSections() }
        .onChange(of: state.neonWelcomeProjects) { _, _ in rebuildNeonSections() }
        .onChange(of: state.neonWelcomeBranches) { _, _ in rebuildNeonSections() }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image("DriftLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .foregroundColor(Theme.text)
                    Text("Drift")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text("PostgreSQL Browser")
                        .font(.system(.caption))
                        .foregroundColor(Theme.textSecondary)
                    if state.isRefreshing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(Theme.accent)
                            .padding(.top, 4)
                    }
                }

                Button {
                    state.showConnectionSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(.caption).weight(.medium))
                        Text("New Connection")
                            .font(.system(.caption, weight: .medium))
                    }
                    .frame(width: 180)
                }
                .buttonStyle(DriftButtonStyle(isPrimary: true))
            }
            .frame(maxWidth: welcomeSidebarContentWidth)
            .padding(.top, 56)

            if !state.connections.isEmpty {
                savedConnectionsList
                    .frame(maxWidth: welcomeSidebarContentWidth, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 28)
            } else {
                Spacer(minLength: 0)
            }

            if state.isConnecting {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(Theme.accent)
                    .padding(.bottom, 20)
            }

            if let error = state.connectionError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(Theme.error)
                    .lineLimit(3)
                    .padding(8)
                    .background(Theme.error.opacity(0.1))
                    .cornerRadius(Theme.smallRadius)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: state.neon.isConfigured ? welcomeSidebarWidth : .infinity,
               maxHeight: .infinity,
               alignment: .top)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var sortedConnections: [SavedConnection] {
        Array(state.connections.reversed())
    }

    private var favoriteConnections: [SavedConnection] {
        sortedConnections.filter(isFavoriteConnection)
    }

    private var recentConnectionsOnly: [SavedConnection] {
        sortedConnections.filter { !isFavoriteConnection($0) }
    }

    private var shortcutConnections: [SavedConnection] {
        Array((favoriteConnections + recentConnectionsOnly).prefix(9))
    }

    private var savedConnectionsList: some View {
        ScrollView(showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !favoriteConnections.isEmpty {
                    savedConnectionsSection(title: "FAVOURITES", connections: favoriteConnections)
                }
                if !recentConnectionsOnly.isEmpty {
                    savedConnectionsSection(title: "RECENT", connections: recentConnectionsOnly)
                }
            }
        }
        .frame(width: welcomeSidebarContentWidth)
    }

    private func savedConnectionsSection(title: String, connections: [SavedConnection]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption2, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
                .padding(.bottom, 2)

            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(connections, id: \.id) { conn in
                    savedConnectionRow(conn)
                }
            }
        }
    }

    private func savedConnectionRow(_ conn: SavedConnection) -> some View {
        HStack(spacing: 6) {
            Button {
                Task { await state.connect(to: conn) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: connectionIconName(for: conn))
                        .font(.system(.caption2))
                        .foregroundColor(connectionIconColor(for: conn))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conn.displayName)
                            .font(.system(.caption, weight: .medium))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                        if let created = neonCreatedLabel(for: conn) {
                            Text(created)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    shortcutBadge(for: conn)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { state.removeConnection(conn) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Theme.surface)
        .cornerRadius(Theme.smallRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.smallRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func shortcutBadge(for connection: SavedConnection) -> some View {
        Group {
            if let shortcutIndex = shortcutConnections.firstIndex(where: { $0.id == connection.id }) {
                Kbd("⌘\(shortcutIndex + 1)")
            } else {
                Color.clear
            }
        }
        .frame(width: 28, height: 20, alignment: .trailing)
    }

    private func isFavoriteConnection(_ connection: SavedConnection) -> Bool {
        guard let projectId = connection.neonProjectId,
              let branchId = connection.neonBranchId else { return false }
        return state.isNeonBranchStarred(projectId: projectId, branchId: branchId)
    }

    private func connectionIconName(for connection: SavedConnection) -> String {
        if isFavoriteConnection(connection) {
            return "star.fill"
        }
        return "cylinder.split.1x2"
    }

    private func connectionIconColor(for connection: SavedConnection) -> Color {
        if isFavoriteConnection(connection) {
            return Theme.warning
        }
        return connection.neonProjectId != nil ? Theme.success : Theme.accent
    }

    // MARK: - Right Panel (Neon)

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image("NeonLogo")
                    .resizable()
                    .frame(width: 14, height: 14)
                Text("Neon Databases")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                if state.isLoadingNeonWelcome {
                    ProgressView().scaleEffect(0.5).tint(Theme.accent)
                }
                Kbd("/")

                Button {
                    Task { await state.loadNeonWelcome() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption2)
                    .foregroundColor(Theme.textTertiary)
                TextField("Search connections...", text: $neonSearch)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.text)
                    .focused($neonSearchFocused)
                    .onKeyPress(.escape) {
                        neonSearchFocused = false
                        viewFocused = true
                        return .handled
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface)
            .cornerRadius(Theme.smallRadius)
            .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius).stroke(Theme.border, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        neonBranchHeader

                        Rectangle().fill(Theme.borderSubtle).frame(height: 1)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(neonSections) { section in
                                    neonProjectRow(section)
                                }
                            }
                        }
                    }
                    .frame(
                        width: max(proxy.size.width, neonTableMinWidth),
                        height: proxy.size.height,
                        alignment: .topLeading
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var neonBranchHeader: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 16, height: 1)
            neonBranchSortButton(.name, title: "Branch", width: neonBranchNameColumnWidth, alignment: .leading)
            neonBranchSortButton(.created, title: "Created", width: neonBranchDateColumnWidth, alignment: .trailing)
            neonBranchSortButton(.updated, title: "Updated", width: neonBranchDateColumnWidth, alignment: .trailing)
            Spacer(minLength: 0)
            Color.clear.frame(width: 28, height: 1)
        }
        .frame(minWidth: neonTableMinWidth, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.vertical, 6)
        .background(Theme.surface.opacity(0.55))
    }

    private func neonBranchSortButton(
        _ key: NeonBranchSortKey,
        title: String,
        width: CGFloat,
        alignment: Alignment
    ) -> some View {
        Button {
            if neonBranchSort == key {
                neonBranchSortDescending.toggle()
            } else {
                neonBranchSort = key
                neonBranchSortDescending = key != .name
            }
        } label: {
            HStack(spacing: 4) {
                if alignment == .trailing { Spacer(minLength: 0) }
                Text(title)
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundColor(neonBranchSort == key ? Theme.text : Theme.textTertiary)
                if neonBranchSort == key {
                    Image(systemName: neonBranchSortDescending ? "arrow.down" : "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.accent)
                }
                if alignment == .leading { Spacer(minLength: 0) }
            }
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func neonProjectRow(_ section: NeonProjectSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project header
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundColor(Theme.textTertiary)
                Text(section.project.name)
                    .font(.system(.caption, weight: .medium))
                    .foregroundColor(Theme.text)
                Spacer()
            }
            .frame(minWidth: neonTableMinWidth, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            // Branches
            ForEach(section.branches) { entry in
                let branch = entry.branch
                let isHighlighted = isBranchHighlighted(entry)
                let isStarred = state.isNeonBranchStarred(projectId: section.project.id, branchId: branch.id)
                HStack(spacing: 0) {
                    Button {
                        Task { await state.connectToNeonBranch(project: section.project, branch: branch) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: branch.name == "main" ? "leaf.fill" : "arrow.branch")
                                .font(.system(.caption2))
                                .foregroundColor(branch.name == "main" ? Theme.success : Theme.accent)
                                .frame(width: 16)
                            Text(branch.name)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(isHighlighted ? Theme.text : Theme.textSecondary)
                                .lineLimit(1)
                                .frame(width: neonBranchNameColumnWidth, alignment: .leading)
                            Text(entry.createdLabel)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(Theme.textTertiary)
                                .frame(width: neonBranchDateColumnWidth, alignment: .trailing)
                            Text(entry.updatedLabel)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(Theme.textTertiary)
                                .frame(width: neonBranchDateColumnWidth, alignment: .trailing)
                            Spacer()
                        }
                        .frame(minWidth: neonTableMinWidth - 36, alignment: .leading)
                        .padding(.leading, 32)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(NeonBranchButtonStyle())

                    Button {
                        state.toggleStarNeonBranch(projectId: section.project.id, branchId: branch.id)
                    } label: {
                        Image(systemName: isStarred ? "star.fill" : "star")
                            .font(.system(.caption2))
                            .foregroundColor(isStarred ? Theme.warning : Theme.textTertiary)
                            .frame(width: 28, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(StarButtonStyle())
                    .padding(.trailing, 8)
                }
                .frame(minWidth: neonTableMinWidth, alignment: .leading)
                .background(isHighlighted ? Theme.accent.opacity(0.1) : Color.clear)
            }

            Rectangle().fill(Theme.borderSubtle).frame(height: 1).padding(.horizontal, 16)
        }
    }

    private func compareNeonBranchEntries(_ lhs: NeonBranchEntry, _ rhs: NeonBranchEntry) -> Bool {
        switch neonBranchSort {
        case .name:
            let comparison = lhs.branch.name.localizedCaseInsensitiveCompare(rhs.branch.name)
            if comparison == .orderedSame {
                return lhs.branch.id < rhs.branch.id
            }
            let isAscending = comparison == .orderedAscending
            return neonBranchSortDescending ? !isAscending : isAscending
        case .created:
            return compareNeonDates(
                lhs: lhs.createdDate,
                rhs: rhs.createdDate,
                fallbackLhs: lhs.branch.name,
                fallbackRhs: rhs.branch.name
            )
        case .updated:
            return compareNeonDates(
                lhs: lhs.updatedDate,
                rhs: rhs.updatedDate,
                fallbackLhs: lhs.branch.name,
                fallbackRhs: rhs.branch.name
            )
        }
    }

    private func isBranchHighlighted(_ entry: NeonBranchEntry) -> Bool {
        highlightedNeonBranch?.id == entry.id
    }

    private func rebuildNeonSections() {
        let rebuiltSections = state.neonWelcomeProjects
            .sorted { $0.name < $1.name }
            .compactMap { project -> NeonProjectSection? in
                let rawBranches = state.neonWelcomeBranches[project.id] ?? []
                let filteredBranches = neonSearch.isEmpty
                    ? rawBranches
                    : rawBranches.filter { $0.name.localizedCaseInsensitiveContains(neonSearch) }

                guard !filteredBranches.isEmpty else { return nil }

                let entries = filteredBranches
                    .map { branch in
                        let createdDate = parsedNeonDate(branch.created_at)
                        let updatedDate = parsedNeonDate(branch.updated_at)
                        return NeonBranchEntry(
                            project: project,
                            branch: branch,
                            createdDate: createdDate,
                            updatedDate: updatedDate,
                            createdLabel: formattedNeonDate(createdDate),
                            updatedLabel: formattedNeonDate(updatedDate)
                        )
                    }
                    .sorted(by: compareNeonBranchEntries)

                return NeonProjectSection(project: project, branches: entries)
            }

        neonSections = rebuiltSections
        allNeonBranches = rebuiltSections.flatMap(\.branches)
        if allNeonBranches.isEmpty {
            neonSelectedIndex = -1
        } else if neonSelectedIndex >= allNeonBranches.count {
            neonSelectedIndex = allNeonBranches.count - 1
        }
    }

    private func routeTypedCharacterToNeonSearch(_ press: KeyPress) -> KeyPress.Result {
        guard state.neon.isConfigured else { return .ignored }

        let blockedModifiers: EventModifiers = [.command, .control, .option]
        guard press.modifiers.intersection(blockedModifiers).isEmpty else { return .ignored }
        guard !neonSearchFocused else { return .ignored }

        let typed = press.characters
        guard !typed.isEmpty else { return .ignored }

        neonSelectedIndex = -1
        neonSearchFocused = true
        viewFocused = false
        neonSearch.append(typed)
        return .handled
    }

    private func neonCreatedLabel(for connection: SavedConnection) -> String? {
        guard let projectId = connection.neonProjectId,
              let branchId = connection.neonBranchId,
              let branch = state.neonWelcomeBranches[projectId]?.first(where: { $0.id == branchId }) else {
            return nil
        }
        let created = parsedNeonDate(branch.created_at)
        guard created != nil else { return nil }
        return "Created \(formattedNeonDate(created))"
    }

    private func formattedNeonDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func compareNeonDates(lhs: Date?, rhs: Date?, fallbackLhs: String, fallbackRhs: String) -> Bool {
        switch (lhs, rhs) {
        case let (l?, r?):
            if l == r {
                return fallbackStringComparison(lhs: fallbackLhs, rhs: fallbackRhs)
            }
            return neonBranchSortDescending ? l > r : l < r
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return fallbackStringComparison(lhs: fallbackLhs, rhs: fallbackRhs)
        }
    }

    private func fallbackStringComparison(lhs: String, rhs: String) -> Bool {
        let comparison = lhs.localizedCaseInsensitiveCompare(rhs)
        if comparison == .orderedSame {
            return lhs < rhs
        }
        let isAscending = comparison == .orderedAscending
        return neonBranchSortDescending ? !isAscending : isAscending
    }

    private func parsedNeonDate(_ isoString: String?) -> Date? {
        guard let isoString else { return nil }
        return neonDateFormatter.date(from: isoString)
    }
}

// MARK: - Hover Button Style for Neon branches

struct NeonBranchButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isHovered ? Theme.surfaceHover : Color.clear)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .onHover { isHovered = $0 }
    }
}

struct StarButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isHovered ? Theme.surfaceHover : Color.clear)
            .cornerRadius(4)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onHover { isHovered = $0 }
    }
}
