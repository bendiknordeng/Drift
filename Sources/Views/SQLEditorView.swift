import SwiftUI

struct SQLEditorView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedCells: Set<CellAddress> = []
    @State private var anchorCell: CellAddress?
    @State private var columnWidths: [String: CGFloat] = [:]
    @State private var editorFocusRequestID = 0
    @State private var resultsFocusRequestID = 0

    private var allColumnNames: [String] {
        var names = Set<String>()
        for cols in state.tableColumns.values {
            for col in cols {
                names.insert(col.name)
            }
        }
        // Also include table names
        for schema in state.schemas {
            for table in schema.tables {
                names.insert(table)
            }
        }
        return Array(names).sorted()
    }

    var body: some View {
        VSplitView {
            editorPane
                .frame(minHeight: 150)

            resultsPane
                .frame(minHeight: 100)
        }
        .background(Theme.bg)
        .onAppear { editorFocusRequestID += 1 }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SQL Editor")
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textSecondary)
                Spacer()

                Kbd("⌘⏎")

                Button {
                    Task { await state.executeSQL() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.caption2)
                        Text("Run")
                    }
                }
                .buttonStyle(DriftButtonStyle(isPrimary: true))
                .disabled(state.isSQLRunning || state.sqlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface)

            SQLSyntaxEditor(
                text: $state.sqlText,
                columnHints: allColumnNames,
                onCommandEnter: { Task { await state.executeSQL() } },
                onCommandEscape: { Task { await state.goHome() } },
                onMoveToResults: focusResultsFromEditor,
                focusRequestID: editorFocusRequestID
            )
            .background(Theme.bg)
        }
    }

    private var resultsPane: some View {
        VStack(spacing: 0) {
            resultsHeader

            if let error = state.sqlError {
                Text(error)
                    .font(Theme.monoSmall)
                    .foregroundColor(Theme.error)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let result = state.sqlResult {
                sqlResultGrid(result)
            } else {
                Text("Run a query to see results")
                    .font(.caption)
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var resultsHeader: some View {
        HStack {
            Text("Results")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary)

            if let result = state.sqlResult {
                Text("·  \(result.rowCount) rows  ·  \(String(format: "%.0fms", result.executionTime * 1000))")
                    .font(Theme.monoSmall)
                    .foregroundColor(Theme.textTertiary)
            }

            Spacer()

            if state.isSQLRunning {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(Theme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.surface)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(Theme.border),
            alignment: .bottom
        )
    }

    private func sqlResultGrid(_ data: QueryResultData) -> some View {
        NSDataGridView(
            data: data,
            selectedCells: $selectedCells,
            anchorCell: $anchorCell,
            columnWidths: $columnWidths,
            focusRequestID: resultsFocusRequestID,
            onExitUpFromFirstRow: {
                editorFocusRequestID += 1
            },
            onCommandEscape: { Task { await state.goHome() } },
            uiScale: state.fontScale
        )
    }

    private func focusResultsFromEditor() {
        guard let result = state.sqlResult,
              !result.columns.isEmpty,
              !result.rows.isEmpty else { return }

        if anchorCell == nil {
            let addr = CellAddress(row: 0, col: 0)
            selectedCells = [addr]
            anchorCell = addr
        }
        resultsFocusRequestID += 1
    }
}
