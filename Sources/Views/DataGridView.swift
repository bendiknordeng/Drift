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
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(Theme.accent)
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
            filterRow(data.columns)

            NSDataGridView(
                data: data,
                selectedCells: $selectedCells,
                anchorCell: $anchorCell,
                columnWidths: $columnWidths,
                onSort: { col in Task { await state.toggleSort(column: col) } },
                onLoadMore: { Task { await state.loadMoreRows() } },
                truncated: data.truncated,
                registerForBrowserKeyboardMonitor: true,
                onCommandEscape: { Task { await state.goHome() } },
                uiScale: state.fontScale
            )

            paginationBar(data)
        }
    }

    private func filterRow(_ columns: [ColumnInfo]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 44, height: 28)
                ForEach(columns) { col in
                    let binding = Binding<String>(
                        get: { state.columnFilters[col.name] ?? "" },
                        set: { v in state.updateFilter(column: col.name, value: v) }
                    )
                    TextField("Filter...", text: binding)
                        .textFieldStyle(.plain)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Theme.text)
                        .padding(.horizontal, 8)
                        .frame(width: columnWidths[col.name] ?? 180, height: 28)
                }
            }
        }
        .background(Theme.surface.opacity(0.5))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.borderSubtle), alignment: .bottom)
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
