import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @State private var searchText = ""
    @State private var expandedSchemas: Set<String> = ["public"]
    @State private var selectedIndex = -1

    private var allFilteredTables: [(schema: String, table: String)] {
        filteredSchemas.flatMap { schema in
            schema.tables.map { (schema: schema.name, table: $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textTertiary)
                    .font(.caption)
                TextField("Filter tables...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.text)
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
                        proxy.scrollTo("\(item.schema).\(item.table)", anchor: .center)
                    }
                }
            }

            Divider().background(Theme.border)

            // Bottom actions
            HStack(spacing: 8) {
                Button {
                    state.showConnectionSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
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
