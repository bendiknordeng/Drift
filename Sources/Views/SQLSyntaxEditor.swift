import SwiftUI
import AppKit

/// SQL editor with syntax highlighting and optional column-name autocomplete.
struct SQLSyntaxEditor: NSViewRepresentable {
    @Binding var text: String
    let columnHints: [String]  // Column names for autocomplete
    let onCommandEnter: () -> Void
    let onCommandEscape: (() -> Void)?
    let onMoveToResults: (() -> Void)?
    let focusRequestID: Int

    init(
        text: Binding<String>,
        columnHints: [String],
        onCommandEnter: @escaping () -> Void,
        onCommandEscape: (() -> Void)? = nil,
        onMoveToResults: (() -> Void)? = nil,
        focusRequestID: Int = 0
    ) {
        self._text = text
        self.columnHints = columnHints
        self.onCommandEnter = onCommandEnter
        self.onCommandEscape = onCommandEscape
        self.onMoveToResults = onMoveToResults
        self.focusRequestID = focusRequestID
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false

        let textView = DriftEditorTextView()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = Theme.nsText
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.insertionPointColor = Theme.nsAccent
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.commandEscapeHandler = onCommandEscape
        textView.moveToResultsHandler = onMoveToResults
        textView.autoCompleteHandler = { [weak coordinator = context.coordinator] in
            coordinator?.triggerCompletionIfNeeded()
        }

        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applyHighlighting()
        context.coordinator.lastFocusRequestID = focusRequestID
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textColor = Theme.nsText
        textView.insertionPointColor = Theme.nsAccent
        if let textView = textView as? DriftEditorTextView {
            textView.commandEscapeHandler = onCommandEscape
            textView.moveToResultsHandler = onMoveToResults
            textView.autoCompleteHandler = { [weak coordinator = context.coordinator] in
                coordinator?.triggerCompletionIfNeeded()
            }
        }
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            context.coordinator.applyHighlighting()
            if selected.location <= textView.string.count {
                textView.setSelectedRange(selected)
            }
        }
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            scrollView.window?.makeFirstResponder(textView)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLSyntaxEditor
        weak var textView: NSTextView?
        var lastFocusRequestID: Int = 0

        init(_ parent: SQLSyntaxEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            applyHighlighting()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Cmd+Enter → execute
            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               NSEvent.modifierFlags.contains(.command) {
                parent.onCommandEnter()
                return true
            }
            return false
        }

        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let text = textView.string as NSString
            guard charRange.location + charRange.length <= text.length else { return [] }
            let partial = text.substring(with: charRange).lowercased()

            let keywords = Self.sqlKeywords
            let columns = parent.columnHints
            let all = (keywords + columns).filter { $0.lowercased().hasPrefix(partial) }
            return all
        }

        func triggerCompletionIfNeeded() {
            guard let textView else { return }
            let nsText = textView.string as NSString
            let range = textView.selectedRange()
            guard range.length == 0, range.location <= nsText.length else { return }

            let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
            var start = range.location
            while start > 0 {
                guard let scalar = UnicodeScalar(nsText.character(at: start - 1)) else { break }
                guard wordChars.contains(scalar) else { break }
                start -= 1
            }

            let partialLength = range.location - start
            guard partialLength >= 2 else { return }
            textView.complete(nil)
        }

        func applyHighlighting() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([
                .foregroundColor: Theme.nsText,
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            ], range: fullRange)

            let text = storage.string

            // Keywords (purple)
            for keyword in Self.sqlKeywords {
                let pattern = "\\b\(keyword)\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                        if let range = match?.range {
                            storage.addAttributes([
                                .foregroundColor: Theme.nsAccent,
                                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
                            ], range: range)
                        }
                    }
                }
            }

            // Strings (green)
            if let regex = try? NSRegularExpression(pattern: "'[^']*'", options: []) {
                regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                    if let range = match?.range {
                        storage.addAttribute(.foregroundColor,
                            value: Theme.nsSuccess,
                            range: range)
                    }
                }
            }

            // Numbers (orange)
            if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b", options: []) {
                regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                    if let range = match?.range {
                        storage.addAttribute(.foregroundColor,
                            value: Theme.nsWarning,
                            range: range)
                    }
                }
            }

            // Comments (gray)
            if let regex = try? NSRegularExpression(pattern: "--.*", options: []) {
                regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                    if let range = match?.range {
                        storage.addAttribute(.foregroundColor,
                            value: Theme.nsTextSecondary,
                            range: range)
                    }
                }
            }

            storage.endEditing()
        }

        static let sqlKeywords: [String] = [
            "SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "FULL",
            "ON", "AND", "OR", "NOT", "IN", "IS", "NULL", "LIKE", "ILIKE", "BETWEEN",
            "GROUP", "BY", "HAVING", "ORDER", "ASC", "DESC", "LIMIT", "OFFSET",
            "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
            "CREATE", "TABLE", "ALTER", "DROP", "INDEX", "VIEW", "DATABASE",
            "AS", "DISTINCT", "COUNT", "SUM", "AVG", "MIN", "MAX",
            "UNION", "ALL", "EXISTS", "CASE", "WHEN", "THEN", "ELSE", "END",
            "WITH", "RECURSIVE", "TRUE", "FALSE", "CAST", "COALESCE",
            "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT",
            "RETURNING", "CONFLICT", "DO", "NOTHING"
        ]
    }
}

final class DriftEditorTextView: NSTextView {
    var commandEscapeHandler: (() -> Void)?
    var moveToResultsHandler: (() -> Void)?
    var autoCompleteHandler: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if (event.keyCode == 53 || event.keyCode == 4), modifiers == [.command] {
            commandEscapeHandler?()
            return
        }
        if event.keyCode == 125, modifiers.isEmpty, isCaretOnLastLine {
            moveToResultsHandler?()
            return
        }
        let shouldTriggerCompletion = modifiers.isEmpty && shouldTriggerAutoComplete(for: event)
        super.keyDown(with: event)
        if shouldTriggerCompletion {
            autoCompleteHandler?()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if (event.keyCode == 53 || event.keyCode == 4), modifiers == [.command] {
            commandEscapeHandler?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private var isCaretOnLastLine: Bool {
        let range = selectedRange()
        guard range.length == 0 else { return false }
        let nsText = string as NSString
        let location = min(range.location, nsText.length)
        let prefix = nsText.substring(to: location)
        let currentLine = prefix.reduce(into: 0) { count, char in
            if char == "\n" { count += 1 }
        }
        let totalLines = string.reduce(into: 1) { count, char in
            if char == "\n" { count += 1 }
        }
        return currentLine >= max(0, totalLines - 1)
    }

    private func shouldTriggerAutoComplete(for event: NSEvent) -> Bool {
        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return false }
        let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return characters.unicodeScalars.allSatisfy(wordChars.contains)
    }
}
