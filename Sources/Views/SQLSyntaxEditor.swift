import SwiftUI
import AppKit

/// SQL editor with syntax highlighting and optional column-name autocomplete.
struct SQLSyntaxEditor: NSViewRepresentable {
    @Binding var text: String
    let columnHints: [String]  // Column names for autocomplete
    let onCommandEnter: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor(red: 0.89, green: 0.89, blue: 0.92, alpha: 1.0)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.insertionPointColor = NSColor(red: 0.37, green: 0.42, blue: 0.82, alpha: 1.0)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text

        context.coordinator.textView = textView
        context.coordinator.applyHighlighting()
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            context.coordinator.applyHighlighting()
            if selected.location <= textView.string.count {
                textView.setSelectedRange(selected)
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLSyntaxEditor
        weak var textView: NSTextView?

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

        func applyHighlighting() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([
                .foregroundColor: NSColor(red: 0.89, green: 0.89, blue: 0.92, alpha: 1.0),
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
                                .foregroundColor: NSColor(red: 0.56, green: 0.47, blue: 0.90, alpha: 1.0),
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
                            value: NSColor(red: 0.29, green: 0.87, blue: 0.50, alpha: 1.0),
                            range: range)
                    }
                }
            }

            // Numbers (orange)
            if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b", options: []) {
                regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                    if let range = match?.range {
                        storage.addAttribute(.foregroundColor,
                            value: NSColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1.0),
                            range: range)
                    }
                }
            }

            // Comments (gray)
            if let regex = try? NSRegularExpression(pattern: "--.*", options: []) {
                regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                    if let range = match?.range {
                        storage.addAttribute(.foregroundColor,
                            value: NSColor(red: 0.47, green: 0.47, blue: 0.6, alpha: 1.0),
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
