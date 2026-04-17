import SwiftUI
import AppKit

/// NSTableView-based grid with CELL-level selection, arrow navigation, drag-select, copy.
struct NSDataGridView: NSViewRepresentable {
    let data: QueryResultData
    @Binding var selectedCells: Set<CellAddress>
    @Binding var anchorCell: CellAddress?
    @Binding var columnWidths: [String: CGFloat]
    let onSort: (String) -> Void
    let onLoadMore: () -> Void
    let truncated: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let tableView = DriftCellTableView()
        tableView.style = .plain
        tableView.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        tableView.rowHeight = 26
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.gridColor = NSColor(red: 0.12, green: 0.12, blue: 0.20, alpha: 1.0)
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.allowsColumnSelection = false
        tableView.selectionHighlightStyle = .none  // Disable row selection
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.focusRingType = .none
        tableView.coordinator = context.coordinator

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        context.coordinator.buildColumns(for: data)
        tableView.reloadData()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? DriftCellTableView else { return }

        let colNames = data.columns.map(\.name)
        if context.coordinator.lastColumnNames != colNames {
            context.coordinator.buildColumns(for: data)
            tableView.reloadData()
        } else if context.coordinator.lastRowCount != data.rows.count {
            tableView.reloadData()
            context.coordinator.lastRowCount = data.rows.count
        }

        // Scroll to anchor cell
        if let cell = anchorCell, cell != context.coordinator.lastScrolledCell {
            context.coordinator.lastScrolledCell = cell
            if cell.row < data.rows.count {
                tableView.scrollRowToVisible(cell.row)
                // Horizontal scroll to column (+1 because of row number col at index 0)
                let colIndex = cell.col + 1
                if colIndex < tableView.tableColumns.count {
                    var rect = tableView.rect(ofColumn: colIndex)
                    rect.size.height = tableView.rowHeight
                    rect.origin.y = CGFloat(cell.row) * tableView.rowHeight
                    tableView.scrollToVisible(rect)
                }
            }
        }
    }

    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NSDataGridView
        weak var tableView: DriftCellTableView?
        weak var scrollView: NSScrollView?
        var lastColumnNames: [String] = []
        var lastRowCount: Int = -1
        var lastScrolledCell: CellAddress?
        var dragStart: CellAddress?
        var selectionOrigin: CellAddress?
        var copyFlash = false

        init(_ parent: NSDataGridView) { self.parent = parent }

        func refreshSelectionDisplay() {
            guard let tv = tableView else { return }
            let visibleRange = tv.rows(in: tv.visibleRect)
            let colCount = tv.tableColumns.count
            for row in visibleRange.location..<NSMaxRange(visibleRange) {
                for col in 0..<colCount {
                    guard let cell = tv.view(atColumn: col, row: row, makeIfNecessary: false) as? DriftCellView else { continue }
                    if cell.colIndex >= 0 {
                        let addr = CellAddress(row: row, col: cell.colIndex)
                        cell.isSelected = parent.selectedCells.contains(addr)
                        cell.isFlashing = copyFlash && cell.isSelected
                    } else {
                        cell.isSelected = false
                    }
                }
            }
        }

        func buildColumns(for data: QueryResultData) {
            guard let tv = tableView else { return }
            while let c = tv.tableColumns.first { tv.removeTableColumn(c) }

            let numCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("__row"))
            numCol.title = "#"
            numCol.width = 44
            numCol.minWidth = 30
            numCol.maxWidth = 60
            numCol.resizingMask = []
            tv.addTableColumn(numCol)

            for col in data.columns {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.name))
                column.title = col.name
                column.width = parent.columnWidths[col.name] ?? 180
                column.minWidth = 60
                column.resizingMask = [.userResizingMask]
                tv.addTableColumn(column)
            }
            lastColumnNames = data.columns.map(\.name)
        }

        // MARK: - Data Source

        func numberOfRows(in tableView: NSTableView) -> Int { parent.data.rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let colId = tableColumn?.identifier.rawValue else { return nil }
            let cell = DriftCellView()

            if colId == "__row" {
                cell.label.stringValue = "\(row + 1)"
                cell.label.textColor = NSColor(red: 0.47, green: 0.47, blue: 0.6, alpha: 1.0)
                cell.label.alignment = .center
                cell.isSelected = false
                cell.coordinator = self
                cell.colIndex = -1  // row number column
                cell.rowIndex = row
            } else {
                let colIdx = parent.data.columns.firstIndex { $0.name == colId } ?? 0
                let val = (row < parent.data.rows.count && colIdx < parent.data.rows[row].count)
                    ? parent.data.rows[row][colIdx] : nil
                if let val {
                    cell.label.stringValue = val
                    cell.label.textColor = NSColor(red: 0.89, green: 0.89, blue: 0.92, alpha: 1.0)
                } else {
                    cell.label.stringValue = "NULL"
                    cell.label.textColor = NSColor(red: 0.47, green: 0.47, blue: 0.6, alpha: 1.0)
                }
                cell.label.alignment = .left
                let addr = CellAddress(row: row, col: colIdx)
                cell.isSelected = parent.selectedCells.contains(addr)
                cell.isFlashing = copyFlash && cell.isSelected
                cell.coordinator = self
                cell.colIndex = colIdx
                cell.rowIndex = row
            }

            // Infinite scroll trigger
            if row == parent.data.rows.count - 5 && parent.truncated {
                DispatchQueue.main.async { self.parent.onLoadMore() }
            }
            return cell
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard let col = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
            let name = col.identifier.rawValue
            guard name != "__row" else { return }
            DispatchQueue.main.async {
                self.parent.columnWidths[name] = col.width
            }
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            let name = tableColumn.identifier.rawValue
            guard name != "__row" else { return }
            DispatchQueue.main.async {
                self.parent.onSort(name)
            }
        }

        // Prevent NSTableView from selecting rows internally
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            return false
        }

        func selectionShouldChange(in tableView: NSTableView) -> Bool {
            return false
        }

        // Use custom row view that never draws selection
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            return DriftRowView()
        }

        // MARK: - Cell Selection

        func handleCellClick(row: Int, col: Int, modifiers: NSEvent.ModifierFlags) {
            let addr = CellAddress(row: row, col: col)
            if modifiers.contains(.shift) {
                let origin = selectionOrigin ?? (parent.anchorCell ?? addr)
                let minR = min(origin.row, addr.row), maxR = max(origin.row, addr.row)
                let minC = min(origin.col, addr.col), maxC = max(origin.col, addr.col)
                var s: Set<CellAddress> = []
                for r in minR...maxR { for c in minC...maxC { s.insert(CellAddress(row: r, col: c)) } }
                parent.selectedCells = s
                parent.anchorCell = addr
            } else if modifiers.contains(.command) {
                if parent.selectedCells.contains(addr) {
                    parent.selectedCells.remove(addr)
                } else {
                    parent.selectedCells.insert(addr)
                }
                parent.anchorCell = addr
                selectionOrigin = addr
            } else {
                parent.selectedCells = [addr]
                parent.anchorCell = addr
                selectionOrigin = addr
            }
            refreshSelectionDisplay()
        }

        func handleRowNumberClick(row: Int, modifiers: NSEvent.ModifierFlags) {
            let columnCount = parent.data.columns.count
            if modifiers.contains(.shift) {
                let origin = selectionOrigin ?? (parent.anchorCell ?? CellAddress(row: row, col: 0))
                let minR = min(origin.row, row), maxR = max(origin.row, row)
                var s: Set<CellAddress> = []
                for r in minR...maxR { for c in 0..<columnCount { s.insert(CellAddress(row: r, col: c)) } }
                parent.selectedCells = s
            } else {
                var s: Set<CellAddress> = []
                for c in 0..<columnCount { s.insert(CellAddress(row: row, col: c)) }
                parent.selectedCells = s
                parent.anchorCell = CellAddress(row: row, col: 0)
                selectionOrigin = CellAddress(row: row, col: 0)
            }
            refreshSelectionDisplay()
        }

        // MARK: - Drag Select

        func startDrag(at cell: CellAddress) {
            dragStart = cell
        }

        func extendDrag(to cell: CellAddress) {
            guard let start = dragStart else { return }
            let minR = min(start.row, cell.row), maxR = max(start.row, cell.row)
            let minC = min(start.col, cell.col), maxC = max(start.col, cell.col)
            var s: Set<CellAddress> = []
            for r in minR...maxR { for c in minC...maxC { s.insert(CellAddress(row: r, col: c)) } }
            parent.selectedCells = s
            parent.anchorCell = cell
            refreshSelectionDisplay()
        }

        func endDrag() { dragStart = nil }

        // MARK: - Arrow Navigation

        func moveSelection(dRow: Int, dCol: Int, shift: Bool) {
            guard !parent.data.columns.isEmpty else { return }
            let current = parent.anchorCell ?? CellAddress(row: 0, col: 0)
            let maxRow = parent.data.rows.count - 1
            let maxCol = parent.data.columns.count - 1
            let newRow = max(0, min(maxRow, current.row + dRow))
            let newCol = max(0, min(maxCol, current.col + dCol))
            let addr = CellAddress(row: newRow, col: newCol)

            if shift {
                let origin = selectionOrigin ?? current
                let minR = min(origin.row, addr.row), maxR = max(origin.row, addr.row)
                let minC = min(origin.col, addr.col), maxC = max(origin.col, addr.col)
                var s: Set<CellAddress> = []
                for r in minR...maxR { for c in minC...maxC { s.insert(CellAddress(row: r, col: c)) } }
                parent.selectedCells = s
            } else {
                parent.selectedCells = [addr]
                selectionOrigin = addr
            }
            parent.anchorCell = addr

            if let tv = tableView {
                tv.scrollRowToVisible(newRow)
                let colIdx = newCol + 1
                if colIdx < tv.tableColumns.count {
                    var rect = tv.rect(ofColumn: colIdx)
                    rect.size.height = tv.rowHeight
                    rect.origin.y = CGFloat(newRow) * tv.rowHeight
                    tv.scrollToVisible(rect)
                }
                refreshSelectionDisplay()
            }
        }

        // MARK: - Copy

        func copySelection() {
            let sorted = parent.selectedCells.sorted {
                $0.row == $1.row ? $0.col < $1.col : $0.row < $1.row
            }
            guard !sorted.isEmpty else { return }

            var rows: [[String]] = []
            var curRow = -1
            var curCols: [String] = []
            for addr in sorted {
                if addr.row != curRow {
                    if !curCols.isEmpty { rows.append(curCols) }
                    curCols = []
                    curRow = addr.row
                }
                let val = (addr.row < parent.data.rows.count && addr.col < parent.data.rows[addr.row].count)
                    ? (parent.data.rows[addr.row][addr.col] ?? "NULL") : ""
                curCols.append(val)
            }
            if !curCols.isEmpty { rows.append(curCols) }

            let text = rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)

            copyFlash = true
            refreshSelectionDisplay()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.copyFlash = false
                self.refreshSelectionDisplay()
            }
        }
    }
}

// MARK: - Cell View

class DriftCellView: NSView {
    let label = NSTextField(labelWithString: "")
    var isSelected = false { didSet { needsDisplay = true } }
    var isFlashing = false { didSet { needsDisplay = true } }
    weak var coordinator: NSDataGridView.Coordinator?
    var rowIndex: Int = 0
    var colIndex: Int = 0

    init() {
        super.init(frame: .zero)
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.drawsBackground = false
        label.isBordered = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isSelected {
            let color = isFlashing
                ? NSColor(red: 0.37, green: 0.42, blue: 0.82, alpha: 0.5)
                : NSColor(red: 0.37, green: 0.42, blue: 0.82, alpha: 0.25)
            color.setFill()
            bounds.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let coord = coordinator else { return }
        // Make table view first responder so arrow keys work
        window?.makeFirstResponder(coord.tableView)

        if colIndex == -1 {
            coord.handleRowNumberClick(row: rowIndex, modifiers: event.modifierFlags)
        } else {
            coord.handleCellClick(row: rowIndex, col: colIndex, modifiers: event.modifierFlags)
            if !event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.command) {
                coord.startDrag(at: CellAddress(row: rowIndex, col: colIndex))
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let coord = coordinator, colIndex >= 0 else { return }
        // Convert window coordinates to table view coordinates
        guard let tv = coord.tableView else { return }
        let pointInTable = tv.convert(event.locationInWindow, from: nil)
        let rowAt = tv.row(at: pointInTable)
        let colAt = tv.column(at: pointInTable)
        if rowAt >= 0, colAt >= 1 {
            coord.extendDrag(to: CellAddress(row: rowAt, col: colAt - 1))
        }
    }

    override func mouseUp(with event: NSEvent) {
        coordinator?.endDrag()
    }
}

// MARK: - Row View that never shows selection

class DriftRowView: NSTableRowView {
    override var isSelected: Bool {
        get { false }
        set {}
    }
    override func drawSelection(in dirtyRect: NSRect) {
        // No-op: never draw row selection
    }
    override func drawBackground(in dirtyRect: NSRect) {
        // Use cell-level backgrounds only
    }
}

// MARK: - Table View with Keyboard Handling

class DriftCellTableView: NSTableView {
    weak var coordinator: NSDataGridView.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let cmd = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 126: coordinator?.moveSelection(dRow: -1, dCol: 0, shift: shift); return
        case 125: coordinator?.moveSelection(dRow: 1, dCol: 0, shift: shift); return
        case 123: coordinator?.moveSelection(dRow: 0, dCol: -1, shift: shift); return
        case 124: coordinator?.moveSelection(dRow: 0, dCol: 1, shift: shift); return
        case 8:   // C
            if cmd { coordinator?.copySelection(); return }
        default: break
        }
        super.keyDown(with: event)
    }
}
