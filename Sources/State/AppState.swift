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
    @Published var showConnectionSheet = false
    @Published var showSettings = false
    @Published var showCommandPalette = false
    @Published var showGlobalSearch = false
    @Published var showLLMChat = false

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

    init() {
        connections = store.loadConnections()
        neon.apiKey = store.neonAPIKey
        llm.apiKey = store.llmAPIKey
        starredNeonBranches = Set(UserDefaults.standard.stringArray(forKey: starredKey) ?? [])
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
        await disconnect()
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

            // Save if new
            if !connections.contains(where: { $0.id == connection.id }) {
                connections.append(connection)
                store.saveConnections(connections)
            }

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
        try? await postgres.disconnect()
        isConnected = false
        activeConnection = nil
        schemas = []
        selectedTable = nil
        tableData = nil
        tableColumns = [:]
        columnFilters = [:]
    }

    func removeConnection(_ connection: SavedConnection) {
        connections.removeAll { $0.id == connection.id }
        store.saveConnections(connections)
    }

    // MARK: - Schema

    func loadSchemas() async {
        do {
            schemas = try await postgres.fetchSchemas()
            for schema in schemas {
                for table in schema.tables {
                    let ref = TableRef(schema: schema.name, table: table)
                    tableColumns[ref] = try await postgres.fetchColumns(schema: schema.name, table: table)
                }
            }
        } catch {
            errorMessage = Self.debugDescription(error)
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
        guard let ref = selectedTable, let cols = tableColumns[ref] else { return }
        if showLoading { isLoadingData = true }
        do {
            tableData = try await postgres.fetchTableData(
                schema: ref.schema,
                table: ref.table,
                columns: cols,
                limit: rowLimit,
                offset: currentOffset,
                sortColumn: sortColumn,
                sortDescending: sortDescending,
                filters: columnFilters
            )
        } catch {
            errorMessage = Self.debugDescription(error)
        }
        if showLoading { isLoadingData = false }
    }

    private var isLoadingMore = false

    func loadMoreRows() async {
        guard !isLoadingMore else { return }
        guard let ref = selectedTable, let cols = tableColumns[ref] else { return }
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
            errorMessage = Self.debugDescription(error)
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
        await loadTableData()
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
        do {
            sqlResult = try await postgres.executeSQL(sql)
        } catch {
            sqlError = Self.debugDescription(error)
        }
        isSQLRunning = false
    }

    // MARK: - Global Search

    func performGlobalSearch() async {
        guard let ref = selectedTable, let cols = tableColumns[ref] else { return }
        let query = globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            globalSearchResults = nil
            return
        }

        isSearching = true
        do {
            globalSearchResults = try await postgres.globalSearch(
                schema: ref.schema,
                table: ref.table,
                columns: cols,
                query: query
            )
        } catch {
            errorMessage = Self.debugDescription(error)
        }
        isSearching = false
    }

    // MARK: - LLM

    func askLLM(question: String) async {
        let userMsg = LLMMessage(role: .user, content: question)
        llmMessages.append(userMsg)
        isLLMLoading = true

        do {
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
