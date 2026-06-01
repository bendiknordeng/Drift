import SwiftUI

struct TableSchemaModal: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if let ref = state.selectedTable, let columns = state.selectedTableColumns {
                VStack(spacing: 0) {
                    // Header
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                        Text("Schema: \(ref.schema).\(ref.table)")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundColor(Theme.text)
                        Spacer()
                        Button {
                            state.showSchemaModal = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(.caption))
                                .foregroundColor(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.surface)
                    .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .bottom)

                    // Content
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(columns, id: \.name) { col in
                                HStack(spacing: 10) {
                                    Text(col.name)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                    Text(col.dataType)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(Theme.textTertiary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                Rectangle().fill(Theme.borderSubtle).frame(height: 1)
                            }
                        }
                    }
                    .background(Theme.bg)
                }
                .frame(width: 520, height: 420)
                .background(Theme.surfaceElevated)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .onKeyPress(.escape) {
                    state.showSchemaModal = false
                    return .handled
                }
            } else {
                EmptyView()
            }
        }
    }
}
