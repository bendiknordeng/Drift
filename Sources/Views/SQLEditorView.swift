import SwiftUI

struct SQLEditorView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedCells: Set<CellAddress> = []
    @State private var anchorCell: CellAddress?
    @State private var columnWidths: [String: CGFloat] = [:]
    @State private var editorFocusRequestID = 0
    @State private var resultsFocusRequestID = 0

    private let sqlSnippetShortcuts: [(shortcut: String, snippet: String)] = [
        ("⌘1", "SELECT"),
        ("⌘2", "FROM"),
        ("⌘3", "WHERE"),
        ("⌘4", "JOIN"),
        ("⌘5", "GROUP BY"),
        ("⌘6", "LIMIT")
    ]

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
        VStack(spacing: 12) {
            editorPane
                .frame(height: 280)

            resultsPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.bottom, 12)
        .background(Theme.bg)
        .onAppear { editorFocusRequestID += 1 }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundColor(Theme.accent)
                        Text("SQL Editor")
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.text)
                    }
                    Text("Autocomplete and keyboard-first navigation")
                        .font(.system(.caption2))
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()

                Button {
                    Task { await state.executeSQL() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.caption2)
                        Text("Run")
                        Kbd("⌘⏎", variant: .primary)
                            .padding(.leading, 5)
                            .padding(.trailing, -6)
                    }
                }
                .buttonStyle(DriftButtonStyle(isPrimary: true))
                .disabled(state.isSQLRunning || state.sqlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.editorHeader)

            SQLSyntaxEditor(
                text: $state.sqlText,
                columnHints: allColumnNames,
                onCommandEnter: { Task { await state.executeSQL() } },
                onCommandEscape: { Task { await state.goHome() } },
                onMoveToResults: focusResultsFromEditor,
                focusRequestID: editorFocusRequestID
            )
            .background(Theme.editorSurface)

            sqlSnippetFooter
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.editorSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var sqlSnippetFooter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Text("Quick insert")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)

                ForEach(Array(sqlSnippetShortcuts.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Kbd(item.shortcut)
                        Text(item.snippet)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Theme.surface.opacity(0.7))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(Theme.border),
            alignment: .top
        )
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
        .background(Theme.bg)
        .padding(.horizontal, 12)
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
                DriftSpinner(size: 12, lineWidth: 1.9)
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

        if let anchorCell, anchorCell.row < result.rows.count, anchorCell.col < result.columns.count {
            selectedCells = [anchorCell]
        } else {
            let addr = CellAddress(row: 0, col: 0)
            selectedCells = [addr]
            anchorCell = addr
        }
        resultsFocusRequestID += 1
    }
}
