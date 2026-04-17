import SwiftUI

struct CommandPalette: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    private var results: [(schema: String, table: String)] {
        let allTables = state.schemas.flatMap { schema in
            schema.tables.map { (schema: schema.name, table: $0) }
        }
        if query.isEmpty { return allTables }
        return allTables.filter { item in
            let full = "\(item.schema).\(item.table)"
            return full.localizedCaseInsensitiveContains(query) ||
                   item.table.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textTertiary)
                TextField("Jump to table...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(Theme.text)
                    .focused($isFocused)
                    .onSubmit {
                        selectCurrent()
                    }

                Kbd("⌘P")
            }
            .padding(14)
            .background(Theme.surfaceElevated)

            Divider().background(Theme.border)

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if results.isEmpty {
                            Text("No tables found")
                                .font(.caption)
                                .foregroundColor(Theme.textTertiary)
                                .padding(20)
                        } else {
                            ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                                resultRow(item: item, index: index)
                                    .id(index)
                            }
                        }
                    }
                }
                .onChange(of: selectedIndex) { _, newValue in
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .frame(maxHeight: 350)
        }
        .frame(width: Theme.overlayWidth)
        .background(Theme.overlay)
        .cornerRadius(Theme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .padding(.bottom, 100)
        .onAppear {
            isFocused = true
            selectedIndex = 0
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(results.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            state.showCommandPalette = false
            return .handled
        }
        .onKeyPress(.escape, phases: .down) { press in
            guard press.modifiers.contains(.command), state.isConnected else { return .ignored }
            Task { await state.goHome() }
            return .handled
        }
    }

    private func resultRow(item: (schema: String, table: String), index: Int) -> some View {
        Button {
            selectedIndex = index
            selectCurrent()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tablecells")
                    .font(.caption)
                    .foregroundColor(index == selectedIndex ? Theme.accent : Theme.textTertiary)

                Text(item.schema)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                Text(".")
                    .foregroundColor(Theme.textTertiary)
                Text(item.table)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundColor(Theme.text)

                Spacer()

                if let cols = state.tableColumns[TableRef(schema: item.schema, table: item.table)] {
                    Text("\(cols.count) cols")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(index == selectedIndex ? Theme.accentMuted : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func selectCurrent() {
        guard !results.isEmpty, selectedIndex < results.count else { return }
        let item = results[selectedIndex]
        let ref = TableRef(schema: item.schema, table: item.table)
        state.showCommandPalette = false
        Task { await state.selectTable(ref) }
    }
}
