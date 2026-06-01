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
    var selectedTableColumns: [TableColumn]? {
        guard let ref = selectedTable else { return nil }
        return tableColumns[ref]
    }
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
    @Published var sidebarFocusActiveTableCentered = false
    @Published var sidebarFocusActiveTableRequestID = 0
    @Published var showConnectionSheet = false
    @Published var showSettings = false
    @Published var settingsInitialTab = 0
    @Published var showCommandPalette = false
    @Published var showGlobalSearch = false
    @Published var showLLMChat = false
    @Published var showSchemaModal = false
    @Published var commandPaletteFocusRequestID = 0
    @Published var globalSearchFocusRequestID = 0
    @Published var llmChatFocusRequestID = 0
    @Published var isRefreshing = false

    // Global Search
    @Published var globalSearchQuery = ""
    @Published var globalSearchResults: QueryResultData?
    @Published var isSearching = false

    // LLM
    @Published var llmMessages: [LLMMessage] = []
    @Published var isLLMLoading = false

    // Neon browser (welcome screen)
    @Published var neonAPIKeys: [NeonAPIKey] = []
    @Published var neonWelcomeProjects: [NeonProjectEntry] = []
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

    var hasNeonAPIKeys: Bool {
        neonAPIKeys.contains { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    init() {
        let loadedConnections = deduplicatedConnections(store.loadConnections())
        connections = loadedConnections
        if loadedConnections != store.loadConnections() {
            store.saveConnections(loadedConnections)
        }
        neonAPIKeys = store.loadNeonAPIKeys()
        neon.apiKey = neonAPIKeys.first?.key ?? ""
        llm.apiKey = store.llmAPIKey
        starredNeonBranches = Set(UserDefaults.standard.stringArray(forKey: starredKey) ?? [])
        if let rawAppearance = UserDefaults.standard.string(forKey: appearanceKey),
           let savedAppearance = AppAppearance(rawValue: rawAppearance) {
            appearance = savedAppearance
        }
        if hasNeonAPIKeys {
            Task { await loadNeonWelcome() }
        }
    }

    func neonBranchKey(credentialId: UUID?, projectId: String, branchId: String) -> String {
        if let credentialId {
            return "\(credentialId.uuidString)/\(projectId)/\(branchId)"
        }
        return "\(projectId)/\(branchId)"
    }

    func toggleStarNeonBranch(project: NeonProjectEntry, branchId: String) {
        let key = neonBranchKey(credentialId: project.credential.id, projectId: project.project.id, branchId: branchId)
        if starredNeonBranches.contains(key) {
            starredNeonBranches.remove(key)
        } else {
            starredNeonBranches.insert(key)
        }
        UserDefaults.standard.set(Array(starredNeonBranches), forKey: starredKey)
    }

    func isNeonBranchStarred(project: NeonProjectEntry, branchId: String) -> Bool {
        isNeonBranchStarred(
            projectId: project.project.id,
            branchId: branchId,
            credentialId: project.credential.id
        )
    }

    func isNeonBranchStarred(projectId: String, branchId: String, credentialId: UUID? = nil) -> Bool {
        let scopedKey = neonBranchKey(credentialId: credentialId, projectId: projectId, branchId: branchId)
        let legacyKey = neonBranchKey(credentialId: nil, projectId: projectId, branchId: branchId)
        return starredNeonBranches.contains(scopedKey) || starredNeonBranches.contains(legacyKey)
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
        settingsInitialTab = 0
        showCommandPalette = false
        showGlobalSearch = false
        showLLMChat = false
        showSchemaModal = false
        commandPaletteFocusRequestID = 0
        globalSearchFocusRequestID = 0
        llmChatFocusRequestID = 0
        browserGridFocusRequestID = 0
        sidebarNavigationDirection = 0
        sidebarNavigationRequestID = 0
        sidebarFocusActiveTableCentered = false
        sidebarFocusActiveTableRequestID = 0
    }

    func requestBrowserGridFocus() {
        browserGridFocusRequestID += 1
    }

    func requestSidebarNavigation(direction: Int) {
        guard direction != 0 else { return }
        sidebarNavigationDirection = direction
        sidebarNavigationRequestID += 1
    }

    func requestSidebarFocusActiveTable(centered: Bool = false) {
        sidebarFocusActiveTableCentered = centered
        sidebarFocusActiveTableRequestID += 1
    }

    func openCommandPalette() {
        showCommandPalette = true
        commandPaletteFocusRequestID += 1
    }

    func openGlobalSearch() {
        showGlobalSearch = true
        globalSearchFocusRequestID += 1
    }

    func openLLMChat() {
        showLLMChat = true
        llmChatFocusRequestID += 1
    }

    func openSettings(tab: Int = 0) {
        settingsInitialTab = tab
        showSettings = true
    }

    private func isDisconnectRelatedError(_ error: Error) -> Bool {
        let debug = Self.debugDescription(error)
        return !isConnected ||
            !postgres.isConnected ||
            debug.contains("clientClosedConnection") ||
            debug.contains("notConnected")
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let debug = Self.debugDescription(error)
        return debug.contains("CancellationError")
    }

    private func presentDatabaseErrorIfNeeded(_ error: Error, assign: (String) -> Void) {
        guard !isCancellationError(error) else { return }
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
        neonAPIKeys = store.loadNeonAPIKeys()
        neon.apiKey = neonAPIKeys.first?.key ?? ""
        if hasNeonAPIKeys {
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
            return isNeonBranchStarred(
                projectId: projectId,
                branchId: branchId,
                credentialId: connection.neonCredentialId
            )
        }
        let recents = sorted.filter { connection in
            guard let projectId = connection.neonProjectId,
                  let branchId = connection.neonBranchId else { return true }
            return !isNeonBranchStarred(
                projectId: projectId,
                branchId: branchId,
                credentialId: connection.neonCredentialId
            )
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
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if neonAPIKeys.isEmpty {
            neonAPIKeys = [NeonAPIKey(name: "Default", key: trimmed)]
        } else {
            neonAPIKeys[0].key = trimmed
        }
        saveNeonAPIKeysAndReload()
    }

    func addNeonAPIKey(name: String, key: String) {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var displayName = trimmedName
        if displayName.isEmpty {
            displayName = "Neon Project \(neonAPIKeys.count + 1)"
        }

        if let existingIndex = neonAPIKeys.firstIndex(where: { $0.key == trimmedKey }) {
            neonAPIKeys[existingIndex].name = displayName
        } else {
            neonAPIKeys.append(NeonAPIKey(name: displayName, key: trimmedKey))
        }
        saveNeonAPIKeysAndReload()
    }

    func removeNeonAPIKey(_ apiKey: NeonAPIKey) {
        neonAPIKeys.removeAll { $0.id == apiKey.id }
        saveNeonAPIKeysAndReload()
    }

    private func saveNeonAPIKeysAndReload() {
        store.neonAPIKeys = neonAPIKeys
        neon.apiKey = neonAPIKeys.first?.key ?? ""
        Task { await loadNeonWelcome() }
    }

    func updateLLMAPIKey(_ key: String) {
        llm.apiKey = key
        store.llmAPIKey = key
    }

    // MARK: - Neon Welcome

    func loadNeonWelcome() async {
        let apiKeys = neonAPIKeys.filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !apiKeys.isEmpty else {
            neonWelcomeProjects = []
            neonWelcomeBranches = [:]
            return
        }

        isLoadingNeonWelcome = true
        var projectEntries: [NeonProjectEntry] = []
        var branchesByProject: [String: [NeonBranch]] = [:]

        for apiKey in apiKeys {
            do {
                let orgs = try await neon.fetchOrganizations(apiKey: apiKey.key)
                var projects: [NeonProject] = []
                for org in orgs {
                    let orgProjects = try await neon.fetchProjects(orgId: org.id, apiKey: apiKey.key)
                    projects.append(contentsOf: orgProjects)
                }
                if orgs.isEmpty {
                    projects = try await neon.fetchProjects(orgId: nil, apiKey: apiKey.key)
                }

                for project in projects {
                    let entry = NeonProjectEntry(credential: apiKey, project: project)
                    projectEntries.append(entry)
                    branchesByProject[entry.id] = try await neon.fetchBranches(projectId: project.id, apiKey: apiKey.key)
                }
            } catch {
                continue
            }
        }

        neonWelcomeProjects = projectEntries
        neonWelcomeBranches = branchesByProject
        isLoadingNeonWelcome = false
    }

    func connectToNeonBranch(project: NeonProjectEntry, branch: NeonBranch) async {
        isConnecting = true
        connectionError = nil
        do {
            let apiKey = project.credential.key
            let dbs = try await neon.fetchDatabases(projectId: project.project.id, branchId: branch.id, apiKey: apiKey)
            let roles = try await neon.fetchRoles(projectId: project.project.id, branchId: branch.id, apiKey: apiKey)
            let db = dbs.first?.name ?? "neondb"
            let role = roles.first?.name ?? "neondb_owner"

            let uri = try await neon.fetchConnectionURI(
                projectId: project.project.id,
                branchId: branch.id,
                database: db,
                role: role,
                apiKey: apiKey
            )
            if var conn = SavedConnection.fromConnectionString(uri) {
                conn.name = "\(project.name)/\(branch.name)"
                conn.neonProjectId = project.project.id
                conn.neonBranchId = branch.id
                conn.neonCredentialId = project.credential.id
                isConnecting = false
                await connect(to: conn)
            }
        } catch {
            isConnecting = false
            connectionError = Self.debugDescription(error)
        }
    }
}
