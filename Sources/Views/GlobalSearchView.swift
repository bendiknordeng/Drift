import SwiftUI

struct GlobalSearchView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var selectedCells: Set<CellAddress> = []
    @State private var anchorCell: CellAddress?
    @State private var columnWidths: [String: CGFloat] = [:]
    @State private var searchTask: Task<Void, Never>?
    @State private var navigatingResults = false
    @State private var resultsFocusRequestID = 0
    @FocusState private var focusedField: FocusField?

    private enum FocusField { case search }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            tableIndicator
            Rectangle().fill(Theme.border).frame(height: 1)
            searchResults
        }
        .frame(width: 780, height: 520)
        .background(Theme.overlay)
        .cornerRadius(Theme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .onAppear {
            focusedField = .search
            query = state.globalSearchQuery
        }
        .onKeyPress(.escape) {
            if navigatingResults { navigatingResults = false; focusedField = .search; return .handled }
            state.showGlobalSearch = false
            return .handled
        }
        .onKeyPress(.escape, phases: .down) { press in
            guard press.modifiers.contains(.command), state.isConnected else { return .ignored }
            Task { await state.goHome() }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if let results = state.globalSearchResults,
               !results.columns.isEmpty,
               !results.rows.isEmpty {
                navigatingResults = true
                if anchorCell == nil {
                    let addr = CellAddress(row: 0, col: 0)
                    selectedCells = [addr]
                    anchorCell = addr
                }
                resultsFocusRequestID += 1
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Header

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.textTertiary)
                .font(.system(.body))
            TextField("Search all values...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Theme.text)
                .focused($focusedField, equals: .search)
                .onChange(of: query) { _, _ in debouncedSearch() }

            if state.isSearching {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(Theme.accent)
            }

            Kbd("⌘⇧F")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surfaceElevated)
    }

    @ViewBuilder
    private var tableIndicator: some View {
        if state.selectedTable == nil {
            HStack {
                Image(systemName: "info.circle").font(.caption).foregroundColor(Theme.textTertiary)
                Text("Select a table first").font(.caption).foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        } else if let ref = state.selectedTable {
            HStack(spacing: 6) {
                Image(systemName: "tablecells").font(.caption2).foregroundColor(Theme.textTertiary)
                Text(ref.fullName).font(.system(.caption2, design: .monospaced)).foregroundColor(Theme.textTertiary)
                Spacer()
                if let r = state.globalSearchResults {
                    Text("\(r.rowCount) matches")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(r.rowCount > 0 ? Theme.accent : Theme.textTertiary)
                }
                if !selectedCells.isEmpty {
                    Text("· \(selectedCells.count) sel")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Theme.accent)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 5).background(Theme.surface)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var searchResults: some View {
        if let results = state.globalSearchResults, !results.columns.isEmpty {
            NSDataGridView(
                data: results,
                selectedCells: $selectedCells,
                anchorCell: $anchorCell,
                columnWidths: $columnWidths,
                focusRequestID: resultsFocusRequestID,
                highlightQuery: query,
                onEscape: {
                    navigatingResults = false
                    focusedField = .search
                },
                onExitUpFromFirstRow: {
                    navigatingResults = false
                    focusedField = .search
                },
                onCommandEscape: { Task { await state.goHome() } },
                uiScale: state.fontScale
            )
        } else if state.globalSearchResults != nil {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.title3).foregroundColor(Theme.textTertiary)
                Text("No results").font(.caption).foregroundColor(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                Text("Search across all column values").font(.caption).foregroundColor(Theme.textTertiary)
                Text("Results update as you type").font(.caption2).foregroundColor(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Debounced search

    private func debouncedSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                selectedCells = []
                anchorCell = nil
                navigatingResults = false
            }
            state.globalSearchQuery = query
            await state.performGlobalSearch()
        }
    }
}
