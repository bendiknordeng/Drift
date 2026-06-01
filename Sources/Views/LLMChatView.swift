import SwiftUI

struct LLMChatView: View {
    @EnvironmentObject var state: AppState
    @State private var input = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider().background(Theme.border)

            if !state.llm.isConfigured {
                unconfiguredView
            } else {
                chatMessages
                Divider().background(Theme.border)
                chatInput
            }
        }
        .frame(width: 600, height: 500)
        .background(Theme.overlay)
        .cornerRadius(Theme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .onAppear { focusInput() }
        .onChange(of: state.llmChatFocusRequestID) { _, _ in focusInput() }
        .onKeyPress(.escape) {
            state.showLLMChat = false
            return .handled
        }
        .onKeyPress(.escape, phases: .down) { press in
            guard press.modifiers.contains(.command), state.isConnected else { return .ignored }
            Task { await state.goHome() }
            return .handled
        }
    }

    private var chatHeader: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundColor(Theme.accent)
            Text("AI Query")
                .font(Theme.headerFont)
                .foregroundColor(Theme.text)
            Spacer()

            Kbd("⌘K")
        }
        .padding(14)
        .background(Theme.surfaceElevated)
    }

    private var unconfiguredView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key")
                .font(.title2)
                .foregroundColor(Theme.textTertiary)
            Text("Configure your Claude API key in Settings")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
            Text("Settings > API Keys")
                .font(.caption2)
                .foregroundColor(Theme.textTertiary)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(state.llmMessages) { msg in
                        messageView(msg)
                            .id(msg.id)
                    }

                    if state.isLLMLoading {
                        loadingIndicator
                            .id("loading")
                    }
                }
                .padding(14)
            }
            .onChange(of: state.llmMessages.count) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var loadingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.6)
                .tint(Theme.accent)
            Text("Generating query...")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
    }

    private var chatInput: some View {
        HStack(spacing: 10) {
            TextField("Ask about your data...", text: $input)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Theme.text)
                .focused($isFocused)
                .onSubmit { send() }

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundColor(input.isEmpty ? Theme.textTertiary : Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(input.isEmpty || state.isLLMLoading)
        }
        .padding(14)
        .background(Theme.surface)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if state.isLLMLoading {
                proxy.scrollTo("loading", anchor: .bottom)
            } else if let last = state.llmMessages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        Task { await state.askLLM(question: text) }
    }

    private func focusInput() {
        isFocused = false
        DispatchQueue.main.async {
            isFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFocused = true
        }
    }

    @ViewBuilder
    private func messageView(_ msg: LLMMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            messageHeader(msg)
            messageContent(msg)
            if let sql = msg.sql { sqlBlock(sql) }
            if let result = msg.result { resultBlock(result) }
        }
        .padding(10)
        .background(msg.role == .assistant ? Theme.surface.opacity(0.5) : Color.clear)
        .cornerRadius(Theme.smallRadius)
    }

    private func messageHeader(_ msg: LLMMessage) -> some View {
        HStack(spacing: 6) {
            Image(systemName: msg.role == .user ? "person.circle" : "sparkles")
                .font(.caption)
                .foregroundColor(msg.role == .user ? Theme.textSecondary : Theme.accent)
            Text(msg.role == .user ? "You" : "Drift AI")
                .font(.system(.caption, weight: .semibold))
                .foregroundColor(msg.role == .user ? Theme.textSecondary : Theme.accent)
        }
    }

    private func messageContent(_ msg: LLMMessage) -> some View {
        Text(msg.content)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(Theme.text)
            .textSelection(.enabled)
    }

    private func sqlBlock(_ sql: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Generated SQL")
                .font(.system(.caption2, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
            Text(sql)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.accent)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
                .cornerRadius(Theme.smallRadius)
                .textSelection(.enabled)
        }
    }

    private func resultBlock(_ result: QueryResultData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(result.rowCount) rows  ·  \(String(format: "%.0fms", result.executionTime * 1000))")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(Theme.textTertiary)

            resultTable(result)
        }
    }

    private func resultTable(_ result: QueryResultData) -> some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                resultTableHeader(result.columns)
                resultTableRows(result)
            }
            .cornerRadius(Theme.smallRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.smallRadius)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
    }

    private func resultTableHeader(_ columns: [ColumnInfo]) -> some View {
        HStack(spacing: 0) {
            ForEach(columns) { col in
                Text(col.name)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(minWidth: 80, alignment: .leading)
            }
        }
        .background(Theme.surface)
    }

    private func resultTableRows(_ result: QueryResultData) -> some View {
        ForEach(Array(result.rows.prefix(10).enumerated()), id: \.offset) { index, row in
            resultTableRow(row, columns: result.columns, index: index)
        }
    }

    private func resultTableRow(_ row: [String?], columns: [ColumnInfo], index: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { colIdx, _ in
                let value = colIdx < row.count ? row[colIdx] : nil
                Text(value ?? "NULL")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(value != nil ? Theme.text : Theme.textTertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(minWidth: 80, alignment: .leading)
            }
        }
        .background(index % 2 == 0 ? Color.clear : Theme.surface.opacity(0.3))
    }
}
