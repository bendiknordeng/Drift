import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @State private var searchText = ""
    @State private var expandedSchemas: Set<String> = ["public"]
    @State private var selectedIndex = -1
    @FocusState private var searchFocused: Bool
    @FocusState private var viewFocused: Bool

    private var allFilteredTables: [(schema: String, table: String)] {
        filteredSchemas.flatMap { schema in
            schema.tables.map { (schema: schema.name, table: $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sidebar.left")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                Text("Sidebar")
                    .font(.system(.caption2, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                Kbd("⌘S")
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.surface)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Theme.borderSubtle),
                alignment: .bottom
            )

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textTertiary)
                    .font(.caption)
                TextField("Filter tables...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.text)
                    .focused($searchFocused)
                    .onKeyPress(.rightArrow) {
                        guard state.selectedTable != nil else { return .ignored }
                        state.requestBrowserGridFocus()
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        let tables = allFilteredTables
                        if !tables.isEmpty {
                            selectedIndex = min(selectedIndex + 1, tables.count - 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selectedIndex = max(-1, selectedIndex - 1)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        let tables = allFilteredTables
                        if selectedIndex >= 0, selectedIndex < tables.count {
                            let item = tables[selectedIndex]
                            let ref = TableRef(schema: item.schema, table: item.table)
                            Task { await state.selectTable(ref, pinTab: false) }
                        }
                        return .handled
                    }
                Kbd("⌘P")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        selectedIndex = -1
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.textTertiary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Theme.surface)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Theme.border),
                alignment: .bottom
            )
            .onChange(of: searchText) { _, _ in selectedIndex = -1 }
            .onChange(of: state.selectedTable) { _, newValue in
                if newValue == nil {
                    searchFocused = true
                }
            }
            .onChange(of: state.sidebarNavigationRequestID) { _, _ in
                handleExternalNavigation(direction: state.sidebarNavigationDirection)
            }

            // Schema tree
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredSchemas, id: \.name) { schema in
                            schemaSection(schema)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: selectedIndex) { _, idx in
                    let tables = allFilteredTables
                    if idx >= 0, idx < tables.count {
                        let item = tables[idx]
                        proxy.scrollTo("\(item.schema).\(item.table)")
                    }
                }
                .onChange(of: state.sidebarFocusActiveTableRequestID) { _, _ in
                    focusActiveTable(proxy: proxy, centered: state.sidebarFocusActiveTableCentered)
                }
            }

            Divider().background(Theme.border)

            // Bottom actions
            HStack(spacing: 8) {
                Button {
                    state.showConnectionSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Text("New Connection")
                            .font(.system(.caption, weight: .medium))
                        Kbd("⌘N")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.textSecondary)

                Spacer()

                Button {
                    Task { await state.disconnect() }
                } label: {
                    Image(systemName: "eject")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.textSecondary)

                Button {
                    Task { await state.loadSchemas() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.textSecondary)
            }
            .padding(10)
            .background(Theme.surface)
        }
        .background(Theme.bg)
        .focusable()
        .focused($viewFocused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow, phases: .down) { press in
            guard viewFocused else { return .ignored }
            guard press.modifiers.contains(.option) else { return .ignored }
            let tables = allFilteredTables
            if tables.isEmpty { return .ignored }
            // Move selection down
            selectedIndex = min(selectedIndex + 1, tables.count - 1)
            // Expand the schema of the newly selected row
            if selectedIndex >= 0 && selectedIndex < tables.count {
                let item = tables[selectedIndex]
                expandedSchemas.insert(item.schema)
            }
            return .handled
        }
        .onKeyPress(.upArrow, phases: .down) { press in
            guard viewFocused else { return .ignored }
            guard press.modifiers.contains(.option) else { return .ignored }
            let tables = allFilteredTables
            if tables.isEmpty { return .ignored }
            // Move selection up
            selectedIndex = max(-1, selectedIndex - 1)
            // If moved above first item within a schema, collapse previous schema if selection moved outside
            if selectedIndex >= 0 && selectedIndex < tables.count {
                let item = tables[selectedIndex]
                // Keep current schema expanded
                expandedSchemas.insert(item.schema)
            }
            return .handled
        }
        .onAppear {
            if state.selectedTable == nil {
                searchFocused = true
            }
            viewFocused = true
        }
    }

    private static let hiddenSchemas: Set<String> = [
        "pg_catalog", "information_schema", "pg_toast",
        "drizzle", "_prisma_migrations", "_sqlx_migrations"
    ]

    private var filteredSchemas: [SchemaInfo] {
        let visible = state.schemas.filter { !Self.hiddenSchemas.contains($0.name) }
        if searchText.isEmpty { return visible }
        return visible.compactMap { schema in
            let filtered = schema.tables.filter { $0.localizedCaseInsensitiveContains(searchText) }
            if filtered.isEmpty { return nil }
            return SchemaInfo(name: schema.name, tables: filtered)
        }
    }

    private func schemaSection(_ schema: SchemaInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if expandedSchemas.contains(schema.name) {
                        expandedSchemas.remove(schema.name)
                    } else {
                        expandedSchemas.insert(schema.name)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expandedSchemas.contains(schema.name) ? "chevron.down" : "chevron.right")
                        .font(.system(.caption2).weight(.bold))
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 12)
                    Text(schema.name)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .textCase(.uppercase)
                    Text("\(schema.tables.count)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Theme.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if expandedSchemas.contains(schema.name) {
                ForEach(schema.tables, id: \.self) { table in
                    tableRow(schema: schema.name, table: table)
                }
            }
        }
    }

    private func tableRow(schema: String, table: String) -> some View {
        let ref = TableRef(schema: schema, table: table)
        let isSelected = state.selectedTable == ref
        let tables = allFilteredTables
        let keyboardSelected = selectedIndex >= 0 && selectedIndex < tables.count
            && tables[selectedIndex].schema == schema && tables[selectedIndex].table == table

        return Button {
            Task { await state.selectTable(ref, pinTab: false) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tablecells")
                    .font(.system(.caption))
                    .foregroundColor(isSelected ? Theme.accent : Theme.textTertiary)
                Text(table)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(isSelected ? Theme.text : Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.leading, 16)
            .padding(.vertical, 5)
        }
        .buttonStyle(SidebarRowButtonStyle(isSelected: isSelected, keyboardSelected: keyboardSelected))
        .id("\(schema).\(table)")
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                Task { await state.selectTable(ref, pinTab: true) }
            }
        )
    }

    private func handleExternalNavigation(direction: Int) {
        guard direction != 0 else { return }
        let tables = allFilteredTables
        guard !tables.isEmpty else {
            searchFocused = true
            selectedIndex = -1
            return
        }

        searchFocused = true
        if direction > 0 {
            selectedIndex = min(selectedIndex + 1, tables.count - 1)
        } else {
            selectedIndex = max(-1, selectedIndex - 1)
        }
    }

    private func focusActiveTable(proxy: ScrollViewProxy, centered: Bool) {
        guard let ref = state.selectedTable else { return }

        searchText = ""
        expandedSchemas.insert(ref.schema)
        searchFocused = true

        let visibleSchemas = state.schemas.filter { !Self.hiddenSchemas.contains($0.name) }
        let tables = visibleSchemas.flatMap { schema in
            schema.tables.map { (schema: schema.name, table: $0) }
        }

        guard let index = tables.firstIndex(where: { $0.schema == ref.schema && $0.table == ref.table }) else {
            selectedIndex = -1
            return
        }

        selectedIndex = index
        DispatchQueue.main.async {
            if centered {
                proxy.scrollTo("\(ref.schema).\(ref.table)", anchor: .center)
            } else {
                proxy.scrollTo("\(ref.schema).\(ref.table)")
            }
        }
    }
}

struct SidebarRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    let keyboardSelected: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                keyboardSelected ? Theme.accent.opacity(0.15) :
                isSelected ? Theme.accentMuted :
                isHovered ? Theme.surfaceHover : Color.clear
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .onHover { isHovered = $0 }
    }
}
