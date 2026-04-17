import SwiftUI

struct SQLEditorView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var editorFocused: Bool

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
        .onAppear { editorFocused = true }
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
                onCommandEnter: { Task { await state.executeSQL() } }
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
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                resultHeader(data.columns)
                resultRows(data)
            }
        }
    }

    private let sqlColWidth: CGFloat = 160

    private func resultHeader(_ columns: [ColumnInfo]) -> some View {
        HStack(spacing: 0) {
            ForEach(columns) { col in
                Text(col.name)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(width: sqlColWidth, height: 28, alignment: .leading)
            }
        }
        .background(Theme.surface)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)
    }

    private func resultRows(_ data: QueryResultData) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(data.rows.enumerated()), id: \.offset) { index, row in
                resultRow(row, columns: data.columns, index: index)
            }
        }
    }

    private func resultRow(_ row: [String?], columns: [ColumnInfo], index: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { colIdx, _ in
                cellView(colIdx < row.count ? row[colIdx] : nil)
                    .frame(width: sqlColWidth, height: 26, alignment: .leading)
            }
        }
        .background(index % 2 == 0 ? Color.clear : Theme.surface.opacity(0.3))
    }

    private func cellView(_ value: String?) -> some View {
        Group {
            if let val = value {
                Text(val)
                    .foregroundColor(Theme.text)
            } else {
                Text("NULL")
                    .foregroundColor(Theme.textTertiary)
                    .italic()
            }
        }
        .font(Theme.monoSmall)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}
