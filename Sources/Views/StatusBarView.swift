import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Connection indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(state.isConnected ? Theme.success : Theme.textTertiary)
                    .frame(width: 6, height: 6)
                Text(state.isConnected ? (state.activeConnection?.displayName ?? "Connected") : "Disconnected")
                    .font(Theme.monoSmall)
                    .foregroundColor(Theme.textSecondary)
            }

            if let ref = state.selectedTable {
                Text("·")
                    .foregroundColor(Theme.textTertiary)
                Text(ref.fullName)
                    .font(Theme.monoSmall)
                    .foregroundColor(Theme.textSecondary)

                if let cols = state.tableColumns[ref] {
                    Text("\(cols.count) columns")
                        .font(Theme.monoSmall)
                        .foregroundColor(Theme.textTertiary)
                }
            }

            Spacer()

            if let data = state.tableData, state.activeTab == .browser {
                Text("\(data.rowCount) rows")
                    .font(Theme.monoSmall)
                    .foregroundColor(Theme.textSecondary)
                Text(String(format: "%.0fms", data.executionTime * 1000))
                    .font(Theme.monoSmall)
                    .foregroundColor(Theme.textTertiary)
            }

            // Shortcuts hint
            HStack(spacing: 8) {
                Kbd("⌘P")
                Kbd("⌘⇧F")
                Kbd("⌘K")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Theme.surface)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(Theme.border),
            alignment: .top
        )
    }
}
