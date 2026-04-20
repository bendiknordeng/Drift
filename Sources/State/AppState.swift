import SwiftUI

@MainActor
final class AppState: ObservableObject {
    // Services
    let postgres = PostgresService()
    let neon = NeonService()
    let llm = LLMService()
    let store = ConnectionStore()

    // Connection
    @Published var connections: [SavedConnection] = []
    @Published var activeConnection: SavedConnection?
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var connectionError: String?

    // Schema
    @Published var schemas: [SchemaInfo] = []
    @Published var selectedTable: TableRef?
    @Published var tableColumns: [TableRef: [TableColumn]] = [:]
    @Published var isLoadingSchemas = false

    // Tabs & Navigation
    @Published var openTabs: [TableTab] = []
    @Published var navigationHistory: [TableRef] = []
    @Published var historyIndex: Int = -1

    // Data
    @Published var tableData: QueryResultData?
    @Published var isLoadingData = false
    @Published var currentOffset = 0
    @Published var sortColumn: String?
    @Published var sortDescending = false
    @Published var columnFilters: [String: String] = [:]

    // SQL Editor
    @Published var sqlText = ""
    @Published var sqlResult: QueryResultData?
    @Published var isSQLRunning = false
    @Published var sqlError: String?

    // UI
    @Published var activeTab: ContentTab = .browser
    @Published var appearance: AppAppearance = .dark {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: appearanceKey) }
    }
    @Published var browserGridFocusRequestID = 0
    @Published var sidebarNavigationDirection = 0
    @Published var sidebarNavigationRequestID = 0
    @Published var showConnectionSheet = false
    @Published var showSettings = false
    @Published var showCommandPalette = false
    @Published var showGlobalSearch = false
    @Published var showLLMChat = false
    @Published var isRefreshing = false

    // Global Search
    @Published var globalSearchQuery = ""
    @Published var globalSearchResults: QueryResultData?
    @Published var isSearching = false

    // LLM
    @Published var llmMessages: [LLMMessage] = []
    @Published var isLLMLoading = false

    // Neon browser (welcome screen)
    @Published var neonWelcomeProjects: [NeonProject] = []
    @Published var neonWelcomeBranches: [String: [NeonBranch]] = [:]
    @Published var isLoadingNeonWelcome = false
    @Published var starredNeonBranches: Set<String> = []  // "projectId/branchId"

    // Error
    @Published var errorMessage: String?

    let rowLimit = 500
    @Published var fontScale: CGFloat = 1.0

    private let starredKey = "drift.starred_neon_branches"
    private let appearanceKey = "drift.appearance"
    private var loadingTableColumns: Set<TableRef> = []

    init() {
        let loadedConnections = deduplicatedConnections(store.loadConnections())
        connections = loadedConnections
        if loadedConnections != store.loadConnections() {
            store.saveConnections(loadedConnections)
        }
        neon.apiKey = store.neonAPIKey
        llm.apiKey = store.llmAPIKey
        starredNeonBranches = Set(UserDefaults.standard.stringArray(forKey: starredKey) ?? [])
        if let rawAppearance = UserDefaults.standard.string(forKey: appearanceKey),
           let savedAppearance = AppAppearance(rawValue: rawAppearance) {
            appearance = savedAppearance
        }
        if neon.isConfigured {
            Task { await loadNeonWelcome() }
        }
    }

    func neonBranchKey(_ projectId: String, _ branchId: String) -> String {
        "\(projectId)/\(branchId)"
    }

    func toggleStarNeonBranch(projectId: String, branchId: String) {
        let key = neonBranchKey(projectId, branchId)
        if starredNeonBranches.contains(key) {
            starredNeonBranches.remove(key)
        } else {
            starredNeonBranches.insert(key)
        }
        UserDefaults.standard.set(Array(starredNeonBranches), forKey: starredKey)
    }

    func isNeonBranchStarred(projectId: String, branchId: String) -> Bool {
        starredNeonBranches.contains(neonBranchKey(projectId, branchId))
    }

    func goHome() async {
        resetToWelcomeState()
        try? await postgres.disconnect()
    }

    private func resetToWelcomeState() {
        filterTask?.cancel()

        isConnected = false
        activeConnection = nil
        isConnecting = false
        connectionError = nil

        schemas = []
        selectedTable = nil
        tableColumns = [:]
        isLoadingSchemas = false

        openTabs = []
        navigationHistory = []
        historyIndex = -1

        tableData = nil
        isLoadingData = false
        currentOffset = 0
        sortColumn = nil
        sortDescending = false
        columnFilters = [:]

        sqlResult = nil
        isSQLRunning = false
        sqlError = nil

        globalSearchQuery = ""
        globalSearchResults = nil
        isSearching = false

        activeTab = .browser
        showConnectionSheet = false
        showSettings = false
        showCommandPalette = false
        showGlobalSearch = false
        showLLMChat = false
        browserGridFocusRequestID = 0
        sidebarNavigationDirection = 0
        sidebarNavigationRequestID = 0
    }

    func requestBrowserGridFocus() {
        browserGridFocusRequestID += 1
    }

    func requestSidebarNavigation(direction: Int) {
        guard direction != 0 else { return }
        sidebarNavigationDirection = direction
        sidebarNavigationRequestID += 1
    }

    private func isDisconnectRelatedError(_ error: Error) -> Bool {
        let debug = Self.debugDescription(error)
        return !isConnected ||
            !postgres.isConnected ||
            debug.contains("clientClosedConnection") ||
            debug.contains("notConnected")
    }

    private func presentDatabaseErrorIfNeeded(_ error: Error, assign: (String) -> Void) {
        guard !isDisconnectRelatedError(error) else { return }
        assign(Self.debugDescription(error))
    }

    // MARK: - Connection

    func connect(to connection: SavedConnection) async {
        isConnecting = true
        connectionError = nil
        do {
            try await postgres.connect(config: connection)
            activeConnection = connection
            isConnected = true
            isConnecting = false

            // Keep recents unique by logical connection target while moving the active one to the end.
            let updatedConnections = deduplicatedConnections(
                connections.filter { $0.recentsIdentityKey != connection.recentsIdentityKey } + [connection]
            )
            connections = updatedConnections
            store.saveConnections(updatedConnections)

            await loadSchemas()
        } catch {
            isConnecting = false
            connectionError = Self.debugDescription(error)
        }
    }

    /// PSQLError hides details by default. This extracts the real message.
    static func debugDescription(_ error: Error) -> String {
        let reflected = String(reflecting: error)
        // Extract useful info from the verbose reflected output
        if reflected.contains("serverError") || reflected.contains("message:") {
            return reflected
        }
        let localized = error.localizedDescription
        if localized.contains("PSQLError") {
            return reflected  // localized is useless, show reflected
        }
        return localized
    }

    func disconnect() async {
        resetToWelcomeState()
        try? await postgres.disconnect()
    }

    func refreshCurrentContext() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        connectionError = nil

        if isConnected {
            switch activeTab {
            case .browser:
                await loadSchemas()
                if selectedTable != nil {
                    await loadTableData()
                }
                if showGlobalSearch, !globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await performGlobalSearch()
                }
            case .sql:
                await executeSQL()
            }
            return
        }

        connections = store.loadConnections()
        if neon.isConfigured {
            await loadNeonWelcome()
        } else {
            neonWelcomeProjects = []
            neonWelcomeBranches = [:]
        }
    }

    func removeConnection(_ connection: SavedConnection) {
        connections.removeAll { $0.recentsIdentityKey == connection.recentsIdentityKey }
        store.saveConnections(connections)
    }

    private func deduplicatedConnections(_ items: [SavedConnection]) -> [SavedConnection] {
        var seenKeys: Set<String> = []
        var deduplicatedReversed: [SavedConnection] = []

        for connection in items.reversed() {
            if seenKeys.insert(connection.recentsIdentityKey).inserted {
                deduplicatedReversed.append(connection)
            }
        }

        return deduplicatedReversed.reversed()
    }

    func homeShortcutConnections() -> [SavedConnection] {
        let sorted = Array(connections.reversed())
        let favorites = sorted.filter { connection in
            guard let projectId = connection.neonProjectId,
                  let branchId = connection.neonBranchId else { return false }
            return isNeonBranchStarred(projectId: projectId, branchId: branchId)
        }
        let recents = sorted.filter { connection in
            guard let projectId = connection.neonProjectId,
                  let branchId = connection.neonBranchId else { return true }
            return !isNeonBranchStarred(projectId: projectId, branchId: branchId)
        }
        return Array((favorites + recents).prefix(9))
    }

    // MARK: - Schema

    func loadSchemas() async {
        isLoadingSchemas = true
        defer { isLoadingSchemas = false }
        do {
            let fetchedSchemas = try await postgres.fetchSchemas()
            guard isConnected, postgres.isConnected else { return }
            schemas = fetchedSchemas

            let validRefs = Set(
                fetchedSchemas.flatMap { schema in
                    schema.tables.map { TableRef(schema: schema.name, table: $0) }
                }
            )
            tableColumns = tableColumns.filter { validRefs.contains($0.key) }
        } catch {
            presentDatabaseErrorIfNeeded(error) { [weak self] message in
                self?.errorMessage = message
            }
        }
    }

    // MARK: - Table Data

    func selectTable(_ ref: TableRef, pinTab: Bool = false) async {
        selectedTable = ref
        currentOffset = 0
        sortColumn = nil
        sortDescending = false
        columnFilters = [:]
        activeTab = .browser

        // Tab management
        if let existingIdx = openTabs.firstIndex(where: { $0.ref == ref }) {
            // Already open — just activate, optionally pin
            if pinTab { openTabs[existingIdx].isPinned = true }
        } else if pinTab {
            openTabs.append(TableTab(ref: ref, isPinned: true))
        } else {
            // Replace existing preview tab (unpinned) or add new
            if let previewIdx = openTabs.lastIndex(where: { !$0.isPinned }) {
                openTabs[previewIdx] = TableTab(ref: ref, isPinned: false)
            } else {
                openTabs.append(TableTab(ref: ref, isPinned: false))
            }
        }

        // Navigation history
        if historyIndex < navigationHistory.count - 1 {
            navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
        }
        navigationHistory.append(ref)
        historyIndex = navigationHistory.count - 1

        await loadTableData()
    }

    func pinTab(_ ref: TableRef) {
        if let idx = openTabs.firstIndex(where: { $0.ref == ref }) {
            openTabs[idx].isPinned = true
        }
    }

    func closeTab(_ ref: TableRef) {
        openTabs.removeAll { $0.ref == ref }
        if selectedTable == ref {
            selectedTable = openTabs.last?.ref
            if selectedTable != nil {
                Task { await loadTableData() }
            } else {
                tableData = nil
            }
        }
    }

    func navigateBack() async {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        let ref = navigationHistory[historyIndex]
        selectedTable = ref
        currentOffset = 0
        sortColumn = nil
        sortDescending = false
        columnFilters = [:]
        activeTab = .browser
        await loadTableData()
    }

    func navigateForward() async {
        guard historyIndex < navigationHistory.count - 1 else { return }
        historyIndex += 1
        let ref = navigationHistory[historyIndex]
        selectedTable = ref
        currentOffset = 0
        sortColumn = nil
        sortDescending = false
        columnFilters = [:]
        activeTab = .browser
        await loadTableData()
    }

    func loadTableData(showLoading: Bool = true) async {
        if showLoading { isLoadingData = true }
        defer {
            if showLoading { isLoadingData = false }
        }
        guard let ref = selectedTable,
              let cols = await ensureColumnsLoaded(for: ref) else { return }
        do {
            let data = try await postgres.fetchTableData(
                schema: ref.schema,
                table: ref.table,
                columns: cols,
                limit: rowLimit,
                offset: currentOffset,
                sortColumn: sortColumn,
                sortDescending: sortDescending,
                filters: columnFilters
            )
            guard isConnected, postgres.isConnected else { return }
            tableData = data
        } catch {
            presentDatabaseErrorIfNeeded(error) { [weak self] message in
                self?.errorMessage = message
            }
        }
    }

    private var isLoadingMore = false

    func loadMoreRows() async {
        guard !isLoadingMore else { return }
        guard let ref = selectedTable,
              let cols = await ensureColumnsLoaded(for: ref) else { return }
        guard let current = tableData, current.truncated else { return }
        isLoadingMore = true
        let nextOffset = current.rows.count
        do {
            let more = try await postgres.fetchTableData(
                schema: ref.schema,
                table: ref.table,
                columns: cols,
                limit: rowLimit,
                offset: nextOffset,
                sortColumn: sortColumn,
                sortDescending: sortDescending,
                filters: columnFilters
            )
            guard isConnected, postgres.isConnected else {
                isLoadingMore = false
                return
            }
            // Append rows to existing data
            let combinedRows = current.rows + more.rows
            tableData = QueryResultData(
                columns: current.columns,
                rows: combinedRows,
                rowCount: more.rowCount,
                executionTime: current.executionTime,
                truncated: more.truncated
            )
        } catch {
            presentDatabaseErrorIfNeeded(error) { [weak self] message in
                self?.errorMessage = message
            }
        }
        isLoadingMore = false
    }

    func toggleSort(column: String) async {
        if sortColumn == column {
            sortDescending.toggle()
        } else {
            sortColumn = column
            sortDescending = false
        }
        currentOffset = 0
        await loadTableData(showLoading: false)
    }

    private var filterTask: Task<Void, Never>?

    func updateFilter(column: String, value: String) {
        columnFilters[column] = value
        currentOffset = 0
        // Debounce: cancel previous, wait 300ms before querying
        filterTask?.cancel()
        filterTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await loadTableData(showLoading: false)
        }
    }

    func nextPage() async {
        currentOffset += rowLimit
        await loadTableData()
    }

    func previousPage() async {
        currentOffset = max(0, currentOffset - rowLimit)
        await loadTableData()
    }

    // MARK: - SQL Editor

    func executeSQL() async {
        let sql = sqlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else { return }
        isSQLRunning = true
        sqlError = nil
        defer { isSQLRunning = false }
        do {
            sqlResult = try await postgres.executeSQL(sql)
        } catch {
            presentDatabaseErrorIfNeeded(error) { [weak self] message in
                self?.sqlError = message
            }
        }
    }

    // MARK: - Global Search

    func performGlobalSearch() async {
        guard let ref = selectedTable,
              let cols = await ensureColumnsLoaded(for: ref) else { return }
        let query = globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            globalSearchResults = nil
            return
        }

        isSearching = true
        defer { isSearching = false }
        do {
            globalSearchResults = try await postgres.globalSearch(
                schema: ref.schema,
                table: ref.table,
                columns: cols,
                query: query
            )
        } catch {
            presentDatabaseErrorIfNeeded(error) { [weak self] message in
                self?.errorMessage = message
            }
        }
    }

    // MARK: - LLM

    func askLLM(question: String) async {
        let userMsg = LLMMessage(role: .user, content: question)
        llmMessages.append(userMsg)
        isLLMLoading = true

        do {
            await ensureAllTableColumnsLoadedForSchemaContext()
            let context = llm.buildSchemaContext(schemas: schemas, columns: tableColumns)
            let response = try await llm.generateSQL(userQuery: question, schemaContext: context)

            var assistantMsg = LLMMessage(role: .assistant, content: response.explanation, sql: response.sql)

            // Auto-execute the SQL
            let result = try await postgres.executeSQL(response.sql)
            assistantMsg.result = result

            llmMessages.append(assistantMsg)
        } catch {
            llmMessages.append(LLMMessage(role: .assistant, content: "Error: \(error.localizedDescription)"))
        }
        isLLMLoading = false
    }

    private func ensureColumnsLoaded(for ref: TableRef) async -> [TableColumn]? {
        if let cols = tableColumns[ref] {
            return cols
        }

        if loadingTableColumns.contains(ref) {
            while loadingTableColumns.contains(ref) {
                try? await Task.sleep(for: .milliseconds(25))
            }
            return tableColumns[ref]
        }

        loadingTableColumns.insert(ref)
        defer { loadingTableColumns.remove(ref) }

        do {
            let cols = try await postgres.fetchColumns(schema: ref.schema, table: ref.table)
            guard isConnected, postgres.isConnected else { return nil }
            tableColumns[ref] = cols
            return cols
        } catch {
            presentDatabaseErrorIfNeeded(error) { [weak self] message in
                self?.errorMessage = message
            }
            return nil
        }
    }

    private func ensureAllTableColumnsLoadedForSchemaContext() async {
        let totalTableCount = schemas.reduce(into: 0) { count, schema in
            count += schema.tables.count
        }
        guard totalTableCount > 0, tableColumns.count < totalTableCount else { return }

        do {
            let metadata = try await postgres.fetchSchemaMetadata()
            guard isConnected, postgres.isConnected else { return }
            schemas = metadata.schemas
            tableColumns = metadata.columnsByTable
        } catch {
            presentDatabaseErrorIfNeeded(error) { [weak self] message in
                self?.errorMessage = message
            }
        }
    }

    // MARK: - Settings

    func updateNeonAPIKey(_ key: String) {
        neon.apiKey = key
        store.neonAPIKey = key
        if neon.isConfigured { Task { await loadNeonWelcome() } }
    }

    func updateLLMAPIKey(_ key: String) {
        llm.apiKey = key
        store.llmAPIKey = key
    }

    // MARK: - Neon Welcome

    func loadNeonWelcome() async {
        guard neon.isConfigured else { return }
        isLoadingNeonWelcome = true
        do {
            let orgs = try await neon.fetchOrganizations()
            var allProjects: [NeonProject] = []
            for org in orgs {
                let projects = try await neon.fetchProjects(orgId: org.id)
                allProjects.append(contentsOf: projects)
            }
            if orgs.isEmpty {
                allProjects = try await neon.fetchProjects(orgId: nil)
            }
            neonWelcomeProjects = allProjects

            // Fetch branches for each project
            for project in allProjects {
                let branches = try await neon.fetchBranches(projectId: project.id)
                neonWelcomeBranches[project.id] = branches
            }
        } catch {
            // Silent fail on welcome screen
        }
        isLoadingNeonWelcome = false
    }

    func connectToNeonBranch(project: NeonProject, branch: NeonBranch) async {
        isConnecting = true
        connectionError = nil
        do {
            let dbs = try await neon.fetchDatabases(projectId: project.id, branchId: branch.id)
            let roles = try await neon.fetchRoles(projectId: project.id, branchId: branch.id)
            let db = dbs.first?.name ?? "neondb"
            let role = roles.first?.name ?? "neondb_owner"

            let uri = try await neon.fetchConnectionURI(
                projectId: project.id, branchId: branch.id, database: db, role: role
            )
            if var conn = SavedConnection.fromConnectionString(uri) {
                conn.name = "\(project.name)/\(branch.name)"
                conn.neonProjectId = project.id
                conn.neonBranchId = branch.id
                isConnecting = false
                await connect(to: conn)
            }
        } catch {
            isConnecting = false
            connectionError = Self.debugDescription(error)
        }
    }
}
