import SwiftUI
import AppKit

struct CellAddress: Hashable {
    let row: Int
    let col: Int
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

struct DataGridView: View {
    @EnvironmentObject var state: AppState

    @State private var selectedCells: Set<CellAddress> = []
    @State private var anchorCell: CellAddress?
    @State private var columnWidths: [String: CGFloat] = [:]

    var body: some View {
        VStack(spacing: 0) {
            if state.isLoadingData {
                DriftSpinner(size: 20, lineWidth: 2.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let data = state.tableData {
                gridContent(data)
            } else {
                Text("No data")
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg)
    }

    private func gridContent(_ data: QueryResultData) -> some View {
        VStack(spacing: 0) {
            NSDataGridView(
                data: data,
                selectedCells: $selectedCells,
                anchorCell: $anchorCell,
                columnWidths: $columnWidths,
                columnFilters: state.columnFilters,
                onSort: { col in Task { await state.toggleSort(column: col) } },
                onFilterChange: { col, value in state.updateFilter(column: col, value: value) },
                onLoadMore: { Task { await state.loadMoreRows() } },
                truncated: data.truncated,
                registerForBrowserKeyboardMonitor: true,
                focusRequestID: state.browserGridFocusRequestID,
                onCommandEscape: { Task { await state.goHome() } },
                onFocusActiveTableInSidebar: { state.requestSidebarFocusActiveTable() },
                uiScale: state.fontScale
            )

            paginationBar(data)
        }
    }

    private func paginationBar(_ data: QueryResultData) -> some View {
        HStack(spacing: 8) {
            Text("\(data.rows.count)\(data.truncated ? "+" : "") rows")
                .font(Theme.monoSmall)
                .foregroundColor(Theme.textSecondary)
            if !selectedCells.isEmpty {
                Text("· \(selectedCells.count) selected")
                    .font(Theme.monoSmall)
                    .foregroundColor(Theme.accent)
            }
            Spacer()
            if data.truncated {
                Text("Scroll for more")
                    .font(.system(.caption2))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Theme.surface)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }
}
