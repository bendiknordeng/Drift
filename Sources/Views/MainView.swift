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
                            if state.selectedTable != nil {
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
                    Text(tab.rawValue)
                        .font(.system(.caption, weight: .medium))
                        .foregroundColor(state.activeTab == tab ? Theme.text : Theme.textTertiary)
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
}

// MARK: - Welcome View (no connection)

struct WelcomeView: View {
    @EnvironmentObject var state: AppState
    @State private var neonSearch = ""
    @State private var neonSelectedIndex = -1
    @FocusState private var viewFocused: Bool
    @FocusState private var neonSearchFocused: Bool

    private var allNeonBranches: [(project: NeonProject, branch: NeonBranch)] {
        var result: [(NeonProject, NeonBranch)] = []
        for p in filteredProjects {
            for b in sortedBranches(for: p) {
                result.append((p, b))
            }
        }
        return result
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
        .onAppear { viewFocused = true }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789"), phases: .down) { press in
            let recentList = Array(state.connections.suffix(9).reversed())
            if let digit = Int(String(press.characters)), digit >= 1, digit <= recentList.count {
                let conn = recentList[digit - 1]
                Task { await state.connect(to: conn) }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "/"), phases: .down) { _ in
            if state.neon.isConfigured { neonSearchFocused = true }
            return .handled
        }
        .onKeyPress(.downArrow) {
            let items = allNeonBranches
            if !items.isEmpty { neonSelectedIndex = min(neonSelectedIndex + 1, items.count - 1) }
            return .handled
        }
        .onKeyPress(.upArrow) {
            neonSelectedIndex = max(-1, neonSelectedIndex - 1)
            return .handled
        }
        .onKeyPress(.return) {
            let items = allNeonBranches
            if neonSelectedIndex >= 0, neonSelectedIndex < items.count {
                let item = items[neonSelectedIndex]
                Task { await state.connectToNeonBranch(project: item.project, branch: item.branch) }
                return .handled
            }
            return .ignored
        }
        .onChange(of: neonSearch) { _, _ in neonSelectedIndex = -1 }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            Spacer()

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

                if !state.connections.isEmpty {
                    recentConnections
                }
            }

            Spacer()

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
        .frame(maxWidth: state.neon.isConfigured ? 340 : .infinity)
        .padding(.horizontal, 24)
    }

    private var sortedConnections: [SavedConnection] {
        Array(state.connections.suffix(9).reversed())
    }

    private var recentConnections: some View {
        let recentList = Array(sortedConnections)
        return VStack(alignment: .leading, spacing: 3) {
            Text("RECENT")
                .font(.system(.caption2, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
                .padding(.bottom, 2)

            ForEach(Array(recentList.enumerated()), id: \.element.id) { idx, conn in
                HStack(spacing: 6) {
                    Button {
                        Task { await state.connect(to: conn) }
                    } label: {
                        HStack(spacing: 6) {
                            Kbd("\(idx + 1)")
                            Image(systemName: "cylinder.split.1x2")
                                .font(.system(.caption2))
                                .foregroundColor(conn.neonProjectId != nil ? Theme.success : Theme.accent)
                            Text(conn.displayName)
                                .font(.system(.caption, weight: .medium))
                                .foregroundColor(Theme.text)
                                .lineLimit(1)
                            Spacer()
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
        }
        .frame(width: 290)
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

            Rectangle().fill(Theme.borderSubtle).frame(height: 1)

            // Project list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredProjects) { project in
                        neonProjectRow(project)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var filteredProjects: [NeonProject] {
        let all = state.neonWelcomeProjects.sorted { $0.name < $1.name }
        if neonSearch.isEmpty { return all }
        // Only show projects that have branches matching the search
        return all.filter { project in
            (state.neonWelcomeBranches[project.id] ?? []).contains { $0.name.localizedCaseInsensitiveContains(neonSearch) }
        }
    }

    private func neonProjectRow(_ project: NeonProject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project header
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundColor(Theme.textTertiary)
                Text(project.name)
                    .font(.system(.caption, weight: .medium))
                    .foregroundColor(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            // Branches
            let branches = sortedBranches(for: project)
            ForEach(branches) { branch in
                let isHighlighted = isBranchHighlighted(project: project, branch: branch)
                let isStarred = state.isNeonBranchStarred(projectId: project.id, branchId: branch.id)
                HStack(spacing: 0) {
                    Button {
                        Task { await state.connectToNeonBranch(project: project, branch: branch) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: branch.name == "main" ? "leaf.fill" : "arrow.branch")
                                .font(.system(.caption2))
                                .foregroundColor(branch.name == "main" ? Theme.success : Theme.accent)
                            Text(branch.name)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(isHighlighted ? Theme.text : Theme.textSecondary)
                            Spacer()
                        }
                        .padding(.leading, 32)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(NeonBranchButtonStyle())

                    Button {
                        state.toggleStarNeonBranch(projectId: project.id, branchId: branch.id)
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
                .background(isHighlighted ? Theme.accent.opacity(0.1) : Color.clear)
            }

            Rectangle().fill(Theme.borderSubtle).frame(height: 1).padding(.horizontal, 16)
        }
    }

    private func sortedBranches(for project: NeonProject) -> [NeonBranch] {
        var branches = state.neonWelcomeBranches[project.id] ?? []
        if !neonSearch.isEmpty {
            branches = branches.filter { $0.name.localizedCaseInsensitiveContains(neonSearch) }
        }
        return branches.sorted { a, b in
            let aStarred = state.isNeonBranchStarred(projectId: project.id, branchId: a.id)
            let bStarred = state.isNeonBranchStarred(projectId: project.id, branchId: b.id)
            if aStarred != bStarred { return aStarred }
            if a.name == "main" { return true }
            if b.name == "main" { return false }
            return a.name < b.name
        }
    }

    private func isBranchHighlighted(project: NeonProject, branch: NeonBranch) -> Bool {
        let items = allNeonBranches
        guard neonSelectedIndex >= 0, neonSelectedIndex < items.count else { return false }
        let sel = items[neonSelectedIndex]
        return sel.project.id == project.id && sel.branch.id == branch.id
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
