import SwiftUI

struct GlobalSearchView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var selectedCells: Set<CellAddress> = []
    @State private var anchorCell: CellAddress?
    @State private var copyFlash = false
    @State private var columnWidths: [String: CGFloat] = [:]
    @State private var searchTask: Task<Void, Never>?
    @State private var navigatingResults = false
    @State private var scrollTarget: Int?
    @FocusState private var focusedField: FocusField?

    private enum FocusField { case search, results }

    private let defaultColWidth: CGFloat = 160
    private let minColWidth: CGFloat = 60
    private let rowHeight: CGFloat = 26

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
        .onKeyPress(.downArrow) {
            if !navigatingResults, state.globalSearchResults != nil {
                navigatingResults = true
                focusedField = .results  // release search field focus
                let addr = CellAddress(row: 0, col: 0)
                selectedCells = [addr]
                anchorCell = addr
                scrollTarget = 0
                return .handled
            }
            if navigatingResults { moveResult(dRow: 1, dCol: 0); return .handled }
            return .ignored
        }
        .onKeyPress(.upArrow) {
            if navigatingResults {
                if anchorCell?.row == 0 { navigatingResults = false; focusedField = .search; return .handled }
                moveResult(dRow: -1, dCol: 0); return .handled
            }
            return .ignored
        }
        .onKeyPress(.leftArrow) {
            if navigatingResults { moveResult(dRow: 0, dCol: -1); return .handled }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if navigatingResults { moveResult(dRow: 0, dCol: 1); return .handled }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "c"), phases: .down) { press in
            if press.modifiers.contains(.command) { doCopyToClipboard(); return .handled }
            return .ignored
        }
        .onCopyCommand {
            let items = copyText()
            if !items.isEmpty {
                withAnimation(.easeOut(duration: 0.1)) { copyFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeIn(duration: 0.2)) { copyFlash = false }
                }
            }
            return items.map { NSItemProvider(object: $0 as NSString) }
        }
    }

    private func colWidth(_ name: String) -> CGFloat {
        columnWidths[name] ?? defaultColWidth
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
            let totalW = results.columns.reduce(CGFloat(0)) { $0 + colWidth($1.name) }
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    resultHeader(results.columns, totalW: totalW)

                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(results.rows.enumerated()), id: \.offset) { rowIdx, row in
                                    resultRow(row, columns: results.columns, index: rowIdx)
                                        .id(rowIdx)
                                }
                            }
                        }
                        .task(id: anchorCell) {
                            if let cell = anchorCell {
                                try? await Task.sleep(for: .milliseconds(50))
                                proxy.scrollTo(cell.row, anchor: .center)
                            }
                        }
                    }
                }
                .frame(width: totalW)
            }
            .focusable()
            .focused($focusedField, equals: .results)
            .focusEffectDisabled()
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

    // MARK: - Result Header with resize

    private func resultHeader(_ columns: [ColumnInfo], totalW: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(columns) { col in
                ZStack(alignment: .trailing) {
                    Text(col.name)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(width: colWidth(col.name), height: 28, alignment: .leading)

                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 6, height: 28)
                        .contentShape(Rectangle())
                        .cursor(.resizeLeftRight)
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let cur = colWidth(col.name)
                                    columnWidths[col.name] = max(minColWidth, cur + value.translation.width)
                                }
                        )
                        .offset(x: 3)
                }
                .frame(width: colWidth(col.name), height: 28)
            }
        }
        .background(Theme.surface)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)
    }

    // MARK: - Result Row with selection

    private func resultRow(_ row: [String?], columns: [ColumnInfo], index: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { colIdx, col in
                let addr = CellAddress(row: index, col: colIdx)
                let value = colIdx < row.count ? row[colIdx] : nil
                let isSelected = selectedCells.contains(addr)

                cellContent(value)
                    .frame(width: colWidth(col.name), height: rowHeight, alignment: .leading)
                    .background(
                        isSelected
                            ? (copyFlash ? Theme.accent.opacity(0.45) : Theme.accent.opacity(0.2))
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { handleTap(addr) }
            }
        }
        .background(index % 2 == 0 ? Color.clear : Theme.surface.opacity(0.3))
    }

    private func cellContent(_ value: String?) -> some View {
        Group {
            if let val = value {
                highlightedText(val, query: query)
            } else {
                Text("NULL").foregroundColor(Theme.textTertiary).italic()
            }
        }
        .font(Theme.monoSmall)
        .lineLimit(1)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func highlightedText(_ text: String, query: String) -> some View {
        if query.isEmpty {
            Text(text).foregroundColor(Theme.text)
        } else if let range = text.range(of: query, options: .caseInsensitive) {
            let before = String(text[text.startIndex..<range.lowerBound])
            let match = String(text[range])
            let after = String(text[range.upperBound..<text.endIndex])
            (Text(before).foregroundColor(Theme.text) +
             Text(match).foregroundColor(Theme.accent).bold() +
             Text(after).foregroundColor(Theme.text))
        } else {
            Text(text).foregroundColor(Theme.text)
        }
    }

    // MARK: - Selection & Copy

    private func handleTap(_ addr: CellAddress) {
        if NSEvent.modifierFlags.contains(.shift), let anchor = anchorCell {
            let minR = min(anchor.row, addr.row), maxR = max(anchor.row, addr.row)
            let minC = min(anchor.col, addr.col), maxC = max(anchor.col, addr.col)
            var s: Set<CellAddress> = []
            for r in minR...maxR { for c in minC...maxC { s.insert(CellAddress(row: r, col: c)) } }
            selectedCells = s
        } else if NSEvent.modifierFlags.contains(.command) {
            if selectedCells.contains(addr) { selectedCells.remove(addr) } else { selectedCells.insert(addr) }
            anchorCell = addr
        } else {
            selectedCells = [addr]
            anchorCell = addr
        }
    }

    private func copyText() -> [String] {
        guard let data = state.globalSearchResults, !selectedCells.isEmpty else { return [] }
        let sorted = selectedCells.sorted { $0.row == $1.row ? $0.col < $1.col : $0.row < $1.row }
        var rows: [[String]] = []
        var curRow = -1
        var curCols: [String] = []
        for addr in sorted {
            if addr.row != curRow {
                if !curCols.isEmpty { rows.append(curCols) }
                curCols = []
                curRow = addr.row
            }
            let val = (addr.row < data.rows.count && addr.col < data.rows[addr.row].count)
                ? (data.rows[addr.row][addr.col] ?? "NULL") : ""
            curCols.append(val)
        }
        if !curCols.isEmpty { rows.append(curCols) }
        return [rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")]
    }

    private func moveResult(dRow: Int, dCol: Int) {
        guard let data = state.globalSearchResults, !data.columns.isEmpty else { return }
        let current = anchorCell ?? CellAddress(row: 0, col: 0)
        let newRow = max(0, min(data.rows.count - 1, current.row + dRow))
        let newCol = max(0, min(data.columns.count - 1, current.col + dCol))
        let addr = CellAddress(row: newRow, col: newCol)
        scrollTarget = newRow
        if NSEvent.modifierFlags.contains(.shift) {
            selectedCells.insert(addr)
        } else {
            selectedCells = [addr]
        }
        anchorCell = addr
    }

    private func doCopyToClipboard() {
        let items = copyText()
        guard let text = items.first, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeOut(duration: 0.08)) { copyFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.15)) { copyFlash = false }
        }
    }

    // MARK: - Debounced search

    private func debouncedSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            state.globalSearchQuery = query
            await state.performGlobalSearch()
        }
    }
}
