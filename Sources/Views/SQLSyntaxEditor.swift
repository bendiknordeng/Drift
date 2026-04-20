import SwiftUI
import AppKit

struct SQLSyntaxEditor: NSViewRepresentable {
    @Binding var text: String
    let columnHints: [String]
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
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        ScrollChrome.apply(to: scrollView)

        let textView = SQLTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        context.coordinator.textView = textView
        configure(textView, in: scrollView, coordinator: context.coordinator)
        textView.string = text
        context.coordinator.applyHighlighting(to: textView)

        scrollView.documentView = textView
        context.coordinator.lastFocusRequestID = focusRequestID
        KeyboardMonitor.shared.registerSQLEditor(textView)

        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? SQLTextView else { return }

        configure(textView, in: scrollView, coordinator: context.coordinator)
        KeyboardMonitor.shared.registerSQLEditor(textView)

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(clampedRange(selection, in: textView.string))
        }

        context.coordinator.applyHighlighting(to: textView)

        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            scrollView.window?.makeFirstResponder(textView)
            textView.scrollRangeToVisible(textView.selectedRange())
        }
    }

    private func configure(_ textView: SQLTextView, in scrollView: NSScrollView, coordinator: Coordinator) {
        let palette = Palette(appearance: textView.effectiveAppearance)
        ScrollChrome.apply(to: scrollView)
        scrollView.contentView.backgroundColor = palette.background

        textView.delegate = coordinator
        textView.sqlDelegate = coordinator
        textView.font = Self.editorFont
        textView.textColor = palette.text
        textView.backgroundColor = palette.background
        textView.drawsBackground = true
        textView.insertionPointColor = palette.accent
        textView.textContainerInset = NSSize(width: 14, height: 6)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.typingAttributes = Self.baseTypingAttributes(textColor: palette.text)
    }

    private func clampedRange(_ range: NSRange, in string: String) -> NSRange {
        let length = (string as NSString).length
        let location = min(range.location, length)
        let selectedLength = min(range.length, max(0, length - location))
        return NSRange(location: location, length: selectedLength)
    }

    private static let editorFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private static func baseTypingAttributes(textColor: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: editorFont,
            .foregroundColor: textColor
        ]
    }

    private struct Palette {
        let text: NSColor
        let accent: NSColor
        let background: NSColor

        init(appearance: NSAppearance) {
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                text = NSColor(hex: "E2E2EC")
                accent = NSColor(hex: "7B83EB")
                background = NSColor(hex: "141420")
            } else {
                text = NSColor(hex: "161A24")
                accent = NSColor(hex: "5561D6")
                background = NSColor(hex: "FBFCFF")
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLSyntaxEditor
        weak var textView: SQLTextView?
        var lastFocusRequestID = 0
        private var isApplyingHighlighting = false

        init(_ parent: SQLSyntaxEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? SQLTextView else { return }
            parent.text = textView.string
            applyHighlighting(to: textView)
        }

        func handleCommandEnter() {
            parent.onCommandEnter()
        }

        func handleEscape() {
            parent.onCommandEscape?()
        }

        func moveToResultsIfNeeded(from textView: SQLTextView) -> Bool {
            guard isCaretOnLastLine(textView) else { return false }
            parent.onMoveToResults?()
            return true
        }

        private func isCaretOnLastLine(_ textView: SQLTextView) -> Bool {
            let range = textView.selectedRange()
            guard range.length == 0 else { return false }

            let nsText = textView.string as NSString
            let location = min(range.location, nsText.length)
            let prefix = nsText.substring(to: location)
            let currentLine = prefix.reduce(into: 0) { count, char in
                if char == "\n" { count += 1 }
            }
            let totalLines = textView.string.reduce(into: 1) { count, char in
                if char == "\n" { count += 1 }
            }
            return currentLine >= max(0, totalLines - 1)
        }

        func applyHighlighting(to textView: SQLTextView) {
            guard !isApplyingHighlighting,
                  let textStorage = textView.textStorage else { return }

            isApplyingHighlighting = true
            defer { isApplyingHighlighting = false }

            let palette = HighlightPalette(appearance: textView.effectiveAppearance)
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let selection = textView.selectedRanges

            textStorage.beginEditing()
            textStorage.setAttributes([
                .font: SQLSyntaxEditor.editorFont,
                .foregroundColor: palette.base
            ], range: fullRange)

            Self.commentRegex.enumerateMatches(in: textStorage.string, options: [], range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                textStorage.addAttributes([
                    .foregroundColor: palette.comment
                ], range: range)
            }

            Self.stringRegex.enumerateMatches(in: textStorage.string, options: [], range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                textStorage.addAttributes([
                    .foregroundColor: palette.string
                ], range: range)
            }

            Self.numberRegex.enumerateMatches(in: textStorage.string, options: [], range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                textStorage.addAttributes([
                    .foregroundColor: palette.number
                ], range: range)
            }

            Self.keywordRegex.enumerateMatches(in: textStorage.string, options: [], range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                textStorage.addAttributes([
                    .foregroundColor: palette.keyword
                ], range: range)
            }

            textStorage.endEditing()
            textView.selectedRanges = selection
            textView.typingAttributes = [
                .font: SQLSyntaxEditor.editorFont,
                .foregroundColor: palette.base
            ]
        }

        private struct HighlightPalette {
            let base: NSColor
            let keyword: NSColor
            let string: NSColor
            let number: NSColor
            let comment: NSColor

            init(appearance: NSAppearance) {
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                if isDark {
                    base = NSColor(hex: "E2E2EC")
                    keyword = NSColor(hex: "8FA0FF")
                    string = NSColor(hex: "8CD7A6")
                    number = NSColor(hex: "F5C27A")
                    comment = NSColor(hex: "6F7391")
                } else {
                    base = NSColor(hex: "161A24")
                    keyword = NSColor(hex: "4056D6")
                    string = NSColor(hex: "0F8A4B")
                    number = NSColor(hex: "B56A00")
                    comment = NSColor(hex: "8A93A8")
                }
            }
        }

        private static let keywordRegex: NSRegularExpression = {
            let pattern = #"\b(SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|FULL|ON|AND|OR|NOT|IN|IS|NULL|LIKE|ILIKE|BETWEEN|GROUP|BY|HAVING|ORDER|ASC|DESC|LIMIT|OFFSET|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|INDEX|VIEW|DATABASE|AS|DISTINCT|COUNT|SUM|AVG|MIN|MAX|UNION|ALL|EXISTS|CASE|WHEN|THEN|ELSE|END|WITH|RECURSIVE|TRUE|FALSE|CAST|COALESCE|PRIMARY|KEY|FOREIGN|REFERENCES|CONSTRAINT|DEFAULT|RETURNING|CONFLICT|DO|NOTHING)\b"#
            return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }()

        private static let stringRegex: NSRegularExpression = {
            try! NSRegularExpression(pattern: #"'(?:''|[^'])*'"#, options: [])
        }()

        private static let numberRegex: NSRegularExpression = {
            try! NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?\b"#, options: [])
        }()

        private static let commentRegex: NSRegularExpression = {
            try! NSRegularExpression(pattern: #"--.*$"#, options: [.anchorsMatchLines])
        }()
    }
}

final class SQLTextView: NSTextView {
    weak var sqlDelegate: SQLSyntaxEditor.Coordinator?

    func insertSQLSnippet(_ snippet: String) {
        let replacementRange = selectedRange()
        insertText(snippet, replacementRange: replacementRange)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.keyCode == 125,
           modifiers.isEmpty,
           sqlDelegate?.moveToResultsIfNeeded(from: self) == true {
            return
        }

        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        let modifiers = NSApp.currentEvent?.modifierFlags.intersection([.command, .shift, .option, .control]) ?? []

        if selector == #selector(NSResponder.insertNewline(_:)), modifiers == [.command] {
            sqlDelegate?.handleCommandEnter()
            return
        }

        if selector == #selector(NSResponder.cancelOperation(_:)), modifiers.isEmpty {
            sqlDelegate?.handleEscape()
            return
        }

        if selector == #selector(NSResponder.moveDown(_:)),
           modifiers.isEmpty,
           sqlDelegate?.moveToResultsIfNeeded(from: self) == true {
            return
        }

        super.doCommand(by: selector)
    }
}
