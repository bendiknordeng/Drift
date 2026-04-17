import SwiftUI

struct ConnectionSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case direct = "Direct"
        case connectionString = "Connection String"
        case neon = "Neon"
    }

    @State private var tab: Tab = .direct
    @State private var name = ""
    @State private var host = "localhost"
    @State private var port = "5432"
    @State private var username = "postgres"
    @State private var password = ""
    @State private var database = "postgres"
    @State private var useSSL = false
    @State private var connectionString = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess = false

    // Neon state
    @State private var neonAPIKey = ""
    @State private var neonProjectSearch = ""
    @State private var neonOrgs: [NeonOrganization] = []
    @State private var selectedOrg: NeonOrganization?
    @State private var neonProjects: [NeonProject] = []
    @State private var selectedProject: NeonProject?
    @State private var neonBranches: [NeonBranch] = []
    @State private var selectedBranch: NeonBranch?
    @State private var neonDatabases: [NeonDatabase] = []
    @State private var selectedDatabase: NeonDatabase?
    @State private var neonRoles: [NeonRole] = []
    @State private var selectedRole: NeonRole?
    @State private var neonLoading = false
    @State private var neonError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Connection")
                    .font(Theme.titleFont)
                    .foregroundColor(Theme.text)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            // Tab selector
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        VStack(spacing: 6) {
                            Text(t.rawValue)
                                .font(.system(.caption, weight: .medium))
                                .foregroundColor(tab == t ? Theme.text : Theme.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(tab == t ? Theme.surfaceHover : Color.clear)
                        .cornerRadius(Theme.smallRadius)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider().background(Theme.border)

            // Content
            ScrollView {
                VStack(spacing: 16) {
                    switch tab {
                    case .direct:
                        directForm
                    case .connectionString:
                        connectionStringForm
                    case .neon:
                        neonForm
                    }
                }
                .padding(20)
            }

            Divider().background(Theme.border)

            // Actions
            HStack {
                if let result = testResult {
                    HStack(spacing: 4) {
                        Image(systemName: testSuccess ? "checkmark.circle" : "xmark.circle")
                            .foregroundColor(testSuccess ? Theme.success : Theme.error)
                        Text(result)
                            .font(.caption)
                            .foregroundColor(testSuccess ? Theme.success : Theme.error)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(DriftButtonStyle())

                Button("Test") { testConnection() }
                    .buttonStyle(DriftButtonStyle())
                    .disabled(isTesting)

                Button("Connect") { connectAndDismiss() }
                    .buttonStyle(DriftButtonStyle(isPrimary: true))
            }
            .padding(20)
        }
        .frame(width: 520, height: 560)
        .background(Theme.bg)
        .onAppear {
            neonAPIKey = state.store.neonAPIKey
            // Auto-start Neon flow if API key is already saved
            if tab == .neon && !neonAPIKey.isEmpty && neonProjects.isEmpty {
                startNeonFlow()
            }
        }
        .onChange(of: tab) { _, newTab in
            if newTab == .neon && !neonAPIKey.isEmpty && neonProjects.isEmpty && neonOrgs.isEmpty {
                state.updateNeonAPIKey(neonAPIKey)
                startNeonFlow()
            }
        }
    }

    // MARK: - Direct Connection Form

    private var directForm: some View {
        VStack(spacing: 12) {
            formField("Name (optional)", text: $name, placeholder: "My Database")
            HStack(spacing: 12) {
                formField("Host", text: $host, placeholder: "localhost")
                formField("Port", text: $port, placeholder: "5432")
                    .frame(width: 80)
            }
            formField("Database", text: $database, placeholder: "postgres")
            formField("Username", text: $username, placeholder: "postgres")
            formField("Password", text: $password, placeholder: "password", isSecure: true)

            Toggle("Use SSL", isOn: $useSSL)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .toggleStyle(.switch)
                .tint(Theme.accent)
        }
    }

    // MARK: - Connection String Form

    private var connectionStringForm: some View {
        VStack(spacing: 12) {
            formField("Name (optional)", text: $name, placeholder: "My Database")

            VStack(alignment: .leading, spacing: 4) {
                Text("Connection String")
                    .font(.system(.caption, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                TextEditor(text: $connectionString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 80)
                    .background(Theme.surface)
                    .cornerRadius(Theme.smallRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.smallRadius)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            }

            Text("postgresql://user:password@host:port/database?sslmode=require")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(Theme.textTertiary)
        }
    }

    // MARK: - Neon Form

    private var neonForm: some View {
        VStack(spacing: 16) {
            // API Key — compact when already set
            if neonOrgs.isEmpty && neonProjects.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Neon API Key")
                        .font(.system(.caption, weight: .medium))
                        .foregroundColor(Theme.textSecondary)

                    HStack(spacing: 8) {
                        SecureField("neon_api_key_...", text: $neonAPIKey)
                            .textFieldStyle(DriftTextFieldStyle())

                        Button {
                            state.updateNeonAPIKey(neonAPIKey)
                            startNeonFlow()
                        } label: {
                            Text("Connect to Neon")
                        }
                        .buttonStyle(DriftButtonStyle(isPrimary: true))
                        .disabled(neonAPIKey.isEmpty || neonLoading)
                    }
                }
            } else {
                // Already connected — show compact indicator with change option
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.success)
                        .font(.caption)
                    Text("Neon connected")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    if let org = selectedOrg {
                        Text("· \(org.name)")
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                    Spacer()
                    Button("Change Key") {
                        neonOrgs = []
                        neonProjects = []
                        selectedOrg = nil
                        selectedProject = nil
                        neonBranches = []
                    }
                    .font(.caption)
                    .foregroundColor(Theme.accent)
                    .buttonStyle(.plain)
                }
            }

            if neonLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Theme.accent)
                    Text(neonLoadingStep)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }

            if let error = neonError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(Theme.error)
                    .padding(8)
                    .background(Theme.error.opacity(0.1))
                    .cornerRadius(Theme.smallRadius)
            }

            // Org picker - only if multiple orgs
            if neonOrgs.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Organization")
                        .font(.system(.caption, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                    ForEach(neonOrgs) { org in
                        Button {
                            selectedOrg = org
                            loadNeonProjects(orgId: org.id)
                        } label: {
                            HStack {
                                Image(systemName: "building.2")
                                    .font(.caption)
                                    .foregroundColor(selectedOrg?.id == org.id ? Theme.accent : Theme.textTertiary)
                                Text(org.name)
                                    .font(.system(.caption, weight: .medium))
                                    .foregroundColor(Theme.text)
                                Spacer()
                                if selectedOrg?.id == org.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundColor(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedOrg?.id == org.id ? Theme.accentMuted : Theme.surface)
                            .cornerRadius(Theme.smallRadius)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Projects with search
            if !neonProjects.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project (\(neonProjects.count))")
                        .font(.system(.caption, weight: .medium))
                        .foregroundColor(Theme.textSecondary)

                    if neonProjects.count > 5 {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption2)
                                .foregroundColor(Theme.textTertiary)
                            TextField("Search projects...", text: $neonProjectSearch)
                                .textFieldStyle(.plain)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Theme.text)
                        }
                        .padding(8)
                        .background(Theme.surface)
                        .cornerRadius(Theme.smallRadius)
                        .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius).stroke(Theme.border, lineWidth: 1))
                    }

                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredNeonProjects) { project in
                                Button {
                                    selectedProject = project
                                    loadNeonBranches(projectId: project.id)
                                } label: {
                                    HStack {
                                        Image(systemName: "cylinder.split.1x2")
                                            .font(.caption)
                                            .foregroundColor(selectedProject?.id == project.id ? Theme.accent : Theme.textTertiary)
                                        Text(project.name)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(Theme.text)
                                            .lineLimit(1)
                                        Spacer()
                                        if selectedProject?.id == project.id {
                                            Image(systemName: "checkmark")
                                                .font(.caption)
                                                .foregroundColor(Theme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selectedProject?.id == project.id ? Theme.accentMuted : Theme.surface)
                                    .cornerRadius(Theme.smallRadius)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
            }

            // Branches
            if !neonBranches.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Branch")
                        .font(.system(.caption, weight: .medium))
                        .foregroundColor(Theme.textSecondary)

                    ForEach(neonBranches) { branch in
                        Button {
                            selectedBranch = branch
                            if let project = selectedProject {
                                loadNeonDetails(projectId: project.id, branchId: branch.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: branch.name == "main" ? "leaf.fill" : "arrow.branch")
                                    .font(.caption)
                                    .foregroundColor(branch.name == "main" ? Theme.success : Theme.accent)
                                Text(branch.name)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(Theme.text)
                                Spacer()
                                if selectedBranch?.id == branch.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundColor(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedBranch?.id == branch.id ? Theme.accentMuted : Theme.surface)
                            .cornerRadius(Theme.smallRadius)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Database/Role (auto-selected, only show if multiple)
            if neonDatabases.count > 1 || neonRoles.count > 1 {
                HStack(spacing: 12) {
                    if neonDatabases.count > 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Database")
                                .font(.system(.caption, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                            Picker("", selection: $selectedDatabase) {
                                ForEach(neonDatabases) { db in
                                    Text(db.name).tag(db as NeonDatabase?)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    if neonRoles.count > 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Role")
                                .font(.system(.caption, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                            Picker("", selection: $selectedRole) {
                                ForEach(neonRoles) { role in
                                    Text(role.name).tag(role as NeonRole?)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }
        }
    }

    @State private var neonLoadingStep = ""

    private var filteredNeonProjects: [NeonProject] {
        if neonProjectSearch.isEmpty { return neonProjects }
        return neonProjects.filter { $0.name.localizedCaseInsensitiveContains(neonProjectSearch) }
    }

    // MARK: - Helpers

    private func formField(_ label: String, text: Binding<String>, placeholder: String, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(.caption, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            if isSecure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(DriftTextFieldStyle())
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(DriftTextFieldStyle())
            }
        }
    }

    private func buildConnection() -> SavedConnection? {
        switch tab {
        case .direct:
            return SavedConnection(
                name: name,
                host: host,
                port: Int(port) ?? 5432,
                username: username,
                password: password,
                database: database,
                useSSL: useSSL
            )
        case .connectionString:
            guard var conn = SavedConnection.fromConnectionString(connectionString) else { return nil }
            if !name.isEmpty { conn.name = name }
            return conn
        case .neon:
            guard let project = selectedProject,
                  let branch = selectedBranch else { return nil }
            let db = selectedDatabase ?? neonDatabases.first
            let role = selectedRole ?? neonRoles.first

            Task {
                do {
                    let uri = try await state.neon.fetchConnectionURI(
                        projectId: project.id,
                        branchId: branch.id,
                        database: db?.name ?? "neondb",
                        role: role?.name ?? project.name
                    )
                    if var conn = SavedConnection.fromConnectionString(uri) {
                        conn.name = "\(project.name)/\(branch.name)"
                        conn.neonProjectId = project.id
                        conn.neonBranchId = branch.id
                        await state.connect(to: conn)
                        if state.isConnected {
                            await MainActor.run { dismiss() }
                        }
                    }
                } catch {
                    await MainActor.run { neonError = error.localizedDescription }
                }
            }
            return nil
        }
    }

    private func testConnection() {
        guard let conn = buildConnection() else {
            testResult = "Invalid connection configuration"
            testSuccess = false
            return
        }
        isTesting = true
        testResult = nil
        Task {
            do {
                let service = PostgresService()
                try await service.connect(config: conn)
                try await service.disconnect()
                testResult = "Connection successful!"
                testSuccess = true
            } catch {
                testResult = error.localizedDescription
                testSuccess = false
            }
            isTesting = false
        }
    }

    private func connectAndDismiss() {
        if tab == .neon {
            _ = buildConnection() // Handled async inside, dismisses on success
            return
        }
        guard let conn = buildConnection() else { return }
        Task {
            await state.connect(to: conn)
            if state.isConnected {
                dismiss()
            } else {
                testResult = state.connectionError ?? "Connection failed"
                testSuccess = false
            }
        }
    }

    // MARK: - Neon Loading

    private func startNeonFlow() {
        neonLoading = true
        neonError = nil
        neonLoadingStep = "Fetching organizations..."
        state.neon.apiKey = neonAPIKey
        Task {
            do {
                // Step 1: Get orgs
                let orgs = try await state.neon.fetchOrganizations()
                neonOrgs = orgs

                if orgs.count == 1 {
                    // Single org — auto-select and load projects
                    selectedOrg = orgs.first
                    neonLoadingStep = "Fetching projects..."
                    neonProjects = try await state.neon.fetchProjects(orgId: orgs.first!.id)
                    if neonProjects.count == 1 {
                        // Single project — auto-select and load branches
                        selectedProject = neonProjects.first
                        neonLoadingStep = "Fetching branches..."
                        neonBranches = try await state.neon.fetchBranches(projectId: neonProjects.first!.id)
                    }
                } else if orgs.isEmpty {
                    // Personal account, no org — try without org_id
                    neonLoadingStep = "Fetching projects..."
                    neonProjects = try await state.neon.fetchProjects(orgId: nil)
                    if neonProjects.count == 1 {
                        selectedProject = neonProjects.first
                        neonLoadingStep = "Fetching branches..."
                        neonBranches = try await state.neon.fetchBranches(projectId: neonProjects.first!.id)
                    }
                }
                // Multiple orgs — user picks, handled by UI
            } catch {
                neonError = error.localizedDescription
            }
            neonLoading = false
        }
    }

    private func loadNeonProjects(orgId: String) {
        neonLoading = true
        neonLoadingStep = "Fetching projects..."
        neonError = nil
        Task {
            do {
                neonProjects = try await state.neon.fetchProjects(orgId: orgId)
                selectedProject = nil
                neonBranches = []
                selectedBranch = nil
                neonDatabases = []
                neonRoles = []
                if neonProjects.count == 1 {
                    selectedProject = neonProjects.first
                    neonLoadingStep = "Fetching branches..."
                    neonBranches = try await state.neon.fetchBranches(projectId: neonProjects.first!.id)
                }
            } catch {
                neonError = error.localizedDescription
            }
            neonLoading = false
        }
    }

    private func loadNeonBranches(projectId: String) {
        neonLoading = true
        Task {
            do {
                neonBranches = try await state.neon.fetchBranches(projectId: projectId)
                selectedBranch = nil
                neonDatabases = []
                neonRoles = []
            } catch {
                neonError = error.localizedDescription
            }
            neonLoading = false
        }
    }

    private func loadNeonDetails(projectId: String, branchId: String) {
        neonLoading = true
        Task {
            do {
                async let dbs = state.neon.fetchDatabases(projectId: projectId, branchId: branchId)
                async let roles = state.neon.fetchRoles(projectId: projectId, branchId: branchId)
                neonDatabases = try await dbs
                neonRoles = try await roles
                selectedDatabase = neonDatabases.first
                selectedRole = neonRoles.first
            } catch {
                neonError = error.localizedDescription
            }
            neonLoading = false
        }
    }
}
