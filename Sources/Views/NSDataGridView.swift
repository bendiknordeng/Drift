import SwiftUI
import AppKit

/// NSTableView-based grid with CELL-level selection, arrow navigation, drag-select, copy.
struct NSDataGridView: NSViewRepresentable {
    let data: QueryResultData
    @Binding var selectedCells: Set<CellAddress>
    @Binding var anchorCell: CellAddress?
    @Binding var columnWidths: [String: CGFloat]
    var columnFilters: [String: String] = [:]
    var onSort: ((String) -> Void)? = nil
    var onFilterChange: ((String, String) -> Void)? = nil
    var onLoadMore: (() -> Void)? = nil
    var truncated: Bool = false
    var registerForBrowserKeyboardMonitor = false
    var registerForGlobalSearchKeyboardMonitor = false
    var focusRequestID: Int = 0
    var highlightQuery: String = ""
    var onEscape: (() -> Void)? = nil
    var onExitUpFromFirstRow: (() -> Void)? = nil
    var onCommandEscape: (() -> Void)? = nil
    var onFocusActiveTableInSidebar: (() -> Void)? = nil
    var uiScale: CGFloat = 1.0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        ScrollChrome.apply(to: scrollView)

        let tableView = DriftCellTableView()
        tableView.style = .plain
        tableView.backgroundColor = Theme.nsBg
        tableView.rowHeight = 26
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.gridColor = Theme.nsBorderSubtle
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.allowsColumnSelection = false
        tableView.selectionHighlightStyle = .none  // Disable row selection
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.focusRingType = .none
        tableView.coordinator = context.coordinator
        let headerView = DriftTableHeaderView()
        headerView.coordinator = context.coordinator
        tableView.headerView = headerView

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        if registerForBrowserKeyboardMonitor {
            KeyboardMonitor.shared.registerBrowserGrid(tableView)
        }
        if registerForGlobalSearchKeyboardMonitor {
            KeyboardMonitor.shared.registerGlobalSearchGrid(tableView)
        }
        context.coordinator.buildColumns(for: data)
        tableView.reloadData()
        context.coordinator.lastDataID = data.id
        context.coordinator.lastRowCount = data.rows.count
        context.coordinator.lastFocusRequestID = focusRequestID
        context.coordinator.lastHighlightQuery = highlightQuery
        context.coordinator.lastColorScheme = context.environment.colorScheme
        context.coordinator.lastSelectedCells = selectedCells
        context.coordinator.lastAnchorCell = anchorCell
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? DriftCellTableView else { return }
        ScrollChrome.apply(to: scrollView)
        if registerForBrowserKeyboardMonitor {
            KeyboardMonitor.shared.registerBrowserGrid(tableView)
        }
        if registerForGlobalSearchKeyboardMonitor {
            KeyboardMonitor.shared.registerGlobalSearchGrid(tableView)
        }
        tableView.backgroundColor = Theme.nsBg
        tableView.gridColor = Theme.nsBorderSubtle
        if let headerView = tableView.headerView as? DriftTableHeaderView {
            headerView.coordinator = context.coordinator
        }

        let colNames = data.columns.map(\.name)
        if context.coordinator.lastColumnNames != colNames {
            context.coordinator.buildColumns(for: data)
            tableView.reloadData()
            context.coordinator.lastDataID = data.id
            context.coordinator.lastRowCount = data.rows.count
            context.coordinator.lastHighlightQuery = highlightQuery
            context.coordinator.lastColorScheme = context.environment.colorScheme
        } else if context.coordinator.lastDataID != data.id || context.coordinator.lastRowCount != data.rows.count {
            tableView.reloadData()
            context.coordinator.lastDataID = data.id
            context.coordinator.lastRowCount = data.rows.count
            context.coordinator.lastHighlightQuery = highlightQuery
            context.coordinator.lastColorScheme = context.environment.colorScheme
        } else if context.coordinator.lastHighlightQuery != highlightQuery ||
                    context.coordinator.lastColorScheme != context.environment.colorScheme {
            tableView.reloadData()
            context.coordinator.lastHighlightQuery = highlightQuery
            context.coordinator.lastColorScheme = context.environment.colorScheme
        }
        context.coordinator.refreshHeaderCells(for: data)
        if context.coordinator.lastSelectedCells != selectedCells ||
            context.coordinator.lastAnchorCell != anchorCell {
            context.coordinator.lastSelectedCells = selectedCells
            context.coordinator.lastAnchorCell = anchorCell
            context.coordinator.refreshSelectionDisplay()
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

        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            context.coordinator.focusTableView()
        }
    }

    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NSDataGridView
        weak var tableView: DriftCellTableView?
        weak var scrollView: NSScrollView?
        var lastColumnNames: [String] = []
        var lastRowCount: Int = -1
        var lastDataID: QueryResultData.ID?
        var lastScrolledCell: CellAddress?
        var lastFocusRequestID: Int = 0
        var lastHighlightQuery: String = ""
        var lastColorScheme: ColorScheme?
        var lastSelectedCells: Set<CellAddress> = []
        var lastAnchorCell: CellAddress?
        var dragStart: CellAddress?
        var selectionOrigin: CellAddress?
        var copyFlash = false
        var filterPopover: NSPopover?
        var valuePreviewPopover: NSPopover?

        init(_ parent: NSDataGridView) { self.parent = parent }

        func focusTableView() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let tableView = self.tableView else { return }
                tableView.window?.makeFirstResponder(tableView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, let tableView = self.tableView else { return }
                tableView.window?.makeFirstResponder(tableView)
            }
        }

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
            numCol.headerCell = DriftTableHeaderCell(title: "#", hasFilterButton: false)
            numCol.width = 44
            numCol.minWidth = 30
            numCol.maxWidth = 60
            numCol.resizingMask = []
            tv.addTableColumn(numCol)

            for col in data.columns {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.name))
                column.title = col.name
                column.headerCell = DriftTableHeaderCell(
                    title: col.name,
                    hasFilterButton: parent.onFilterChange != nil,
                    isFilterActive: !(parent.columnFilters[col.name] ?? "").isEmpty
                )
                column.width = parent.columnWidths[col.name] ?? 180
                column.minWidth = 60
                column.resizingMask = [.userResizingMask]
                tv.addTableColumn(column)
            }
            lastColumnNames = data.columns.map(\.name)
        }

        func refreshHeaderCells(for data: QueryResultData) {
            guard let tv = tableView else { return }

            for column in tv.tableColumns {
                let name = column.identifier.rawValue
                let hasFilterButton = name != "__row" && parent.onFilterChange != nil
                let title = name == "__row" ? "#" : name

                if let headerCell = column.headerCell as? DriftTableHeaderCell {
                    headerCell.stringValue = title
                    headerCell.hasFilterButton = hasFilterButton
                    headerCell.isFilterActive = !(parent.columnFilters[name] ?? "").isEmpty
                } else {
                    column.headerCell = DriftTableHeaderCell(
                        title: title,
                        hasFilterButton: hasFilterButton,
                        isFilterActive: !(parent.columnFilters[name] ?? "").isEmpty
                    )
                }
            }

            tv.headerView?.needsDisplay = true
        }

        func showFilterPopover(for tableColumn: NSTableColumn, relativeTo rect: NSRect, in view: NSView) {
            let columnName = tableColumn.identifier.rawValue
            guard columnName != "__row", parent.onFilterChange != nil else { return }

            filterPopover?.close()
            valuePreviewPopover?.close()

            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 240, height: 58)
            popover.contentViewController = NSHostingController(
                rootView: ColumnFilterPopoverView(
                    columnName: columnName,
                    initialValue: parent.columnFilters[columnName] ?? "",
                    onChange: { [weak self] value in
                        guard let self else { return }
                        DispatchQueue.main.async {
                            self.parent.onFilterChange?(columnName, value)
                            self.refreshHeaderCells(for: self.parent.data)
                        }
                    }
                )
            )

            filterPopover = popover
            popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        }

        func showFilterPopoverForFocusedColumn() -> Bool {
            guard parent.onFilterChange != nil,
                  let focusedCell = parent.anchorCell,
                  focusedCell.col >= 0,
                  let tv = tableView,
                  let headerView = tv.headerView else {
                return false
            }

            let columnIndex = focusedCell.col + 1
            guard columnIndex > 0, columnIndex < tv.tableColumns.count else { return false }

            scrollToCell(focusedCell)
            DispatchQueue.main.async { [weak self, weak headerView] in
                guard let self,
                      let headerView,
                      let tv = self.tableView,
                      columnIndex < tv.tableColumns.count else {
                    return
                }

                let tableColumn = tv.tableColumns[columnIndex]
                self.showFilterPopover(
                    for: tableColumn,
                    relativeTo: headerView.headerRect(ofColumn: columnIndex),
                    in: headerView
                )
            }

            return true
        }

        func showValuePreviewForFocusedCell() -> Bool {
            guard let focusedCell = parent.anchorCell,
                  focusedCell.row >= 0,
                  focusedCell.col >= 0,
                  focusedCell.row < parent.data.rows.count,
                  focusedCell.col < parent.data.columns.count,
                  let tv = tableView else {
                return false
            }

            let row = focusedCell.row
            let col = focusedCell.col
            let value = col < parent.data.rows[row].count ? parent.data.rows[row][col] : nil
            let columnName = parent.data.columns[col].name
            let columnIndex = col + 1

            scrollToCell(focusedCell)
            filterPopover?.close()
            valuePreviewPopover?.close()

            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 440, height: 260)
            popover.contentViewController = NSHostingController(
                rootView: CellValuePreviewPopoverView(
                    columnName: columnName,
                    rowNumber: row + 1,
                    value: value
                )
            )

            var rect = tv.rect(ofColumn: columnIndex)
            rect.origin.y = CGFloat(row) * tv.rowHeight
            rect.size.height = tv.rowHeight

            valuePreviewPopover = popover
            popover.show(relativeTo: rect, of: tv, preferredEdge: .maxY)
            return true
        }

        // MARK: - Data Source

        func numberOfRows(in tableView: NSTableView) -> Int { parent.data.rows.count }

        private func cellParagraphStyle(alignment: NSTextAlignment = .left) -> NSParagraphStyle {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            paragraph.alignment = alignment
            return paragraph
        }

        private func cellTextAttributes(
            color: NSColor,
            font: NSFont = DriftCellMetrics.valueFont,
            alignment: NSTextAlignment = .left
        ) -> [NSAttributedString.Key: Any] {
            [
                .foregroundColor: color,
                .font: font,
                .paragraphStyle: cellParagraphStyle(alignment: alignment)
            ]
        }

        private func applyValue(_ value: String?, to cell: DriftCellView) {
            if let value {
                if parent.highlightQuery.isEmpty {
                    cell.label.stringValue = value
                    cell.label.attributedStringValue = NSAttributedString(
                        string: value,
                        attributes: cellTextAttributes(color: Theme.nsText)
                    )
                } else if let range = value.range(of: parent.highlightQuery, options: .caseInsensitive) {
                    let attributed = NSMutableAttributedString(
                        string: value,
                        attributes: cellTextAttributes(color: Theme.nsText)
                    )
                    let nsRange = NSRange(range, in: value)
                    attributed.addAttributes([
                        .foregroundColor: Theme.nsAccent,
                        .font: DriftCellMetrics.valueBoldFont
                    ], range: nsRange)
                    cell.label.attributedStringValue = attributed
                } else {
                    cell.label.stringValue = value
                    cell.label.attributedStringValue = NSAttributedString(
                        string: value,
                        attributes: cellTextAttributes(color: Theme.nsText)
                    )
                }
                cell.label.textColor = Theme.nsText
            } else {
                cell.label.attributedStringValue = NSAttributedString(
                    string: "NULL",
                    attributes: cellTextAttributes(color: Theme.nsTextSecondary)
                )
                cell.label.textColor = Theme.nsTextSecondary
            }
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let colId = tableColumn?.identifier.rawValue else { return nil }
            let identifier = NSUserInterfaceItemIdentifier(colId == "__row" ? "__row_cell" : "__data_cell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? DriftCellView) ?? DriftCellView()
            cell.identifier = identifier

            if colId == "__row" {
                cell.label.stringValue = "\(row + 1)"
                cell.label.attributedStringValue = NSAttributedString(
                    string: "\(row + 1)",
                    attributes: cellTextAttributes(color: Theme.nsTextSecondary, alignment: .center)
                )
                cell.label.textColor = Theme.nsTextSecondary
                cell.label.alignment = .center
                cell.isSelected = false
                cell.isFlashing = false
                cell.coordinator = self
                cell.colIndex = -1  // row number column
                cell.rowIndex = row
            } else {
                let colIdx = parent.data.columns.firstIndex { $0.name == colId } ?? 0
                let val = (row < parent.data.rows.count && colIdx < parent.data.rows[row].count)
                    ? parent.data.rows[row][colIdx] : nil
                applyValue(val, to: cell)
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
                DispatchQueue.main.async { self.parent.onLoadMore?() }
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
            guard let onSort = parent.onSort else { return }
            DispatchQueue.main.async {
                onSort(name)
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

        private func scrollToCell(_ cell: CellAddress) {
            guard let tv = tableView else { return }
            tv.scrollRowToVisible(cell.row)
            let colIndex = cell.col + 1
            if colIndex < tv.tableColumns.count {
                var rect = tv.rect(ofColumn: colIndex)
                rect.size.height = tv.rowHeight
                rect.origin.y = CGFloat(cell.row) * tv.rowHeight
                tv.scrollToVisible(rect)
            }
        }

        private func select(_ addr: CellAddress, shift: Bool) {
            if shift {
                let origin = selectionOrigin ?? parent.anchorCell ?? addr
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
            scrollToCell(addr)
            refreshSelectionDisplay()
        }

        func moveSelection(dRow: Int, dCol: Int, shift: Bool, jumpToEdge: Bool = false) {
            guard !parent.data.columns.isEmpty, !parent.data.rows.isEmpty else { return }

            let initial = CellAddress(row: 0, col: 0)
            if parent.anchorCell == nil && !shift && !jumpToEdge {
                select(initial, shift: false)
                return
            }

            let current = parent.anchorCell ?? initial
            let maxRow = parent.data.rows.count - 1
            let maxCol = parent.data.columns.count - 1
            if dRow < 0 && current.row == 0 && !shift && !jumpToEdge {
                parent.onExitUpFromFirstRow?()
                return
            }
            let newRow: Int
            if jumpToEdge && dRow != 0 {
                newRow = dRow < 0 ? 0 : maxRow
            } else {
                newRow = max(0, min(maxRow, current.row + dRow))
            }

            let newCol: Int
            if jumpToEdge && dCol != 0 {
                newCol = dCol < 0 ? 0 : maxCol
            } else {
                newCol = max(0, min(maxCol, current.col + dCol))
            }

            let addr = CellAddress(row: newRow, col: newCol)
            select(addr, shift: shift)
        }

        func selectAllCells() {
            guard !parent.data.columns.isEmpty, !parent.data.rows.isEmpty else { return }

            var allCells: Set<CellAddress> = []
            for row in 0..<parent.data.rows.count {
                for col in 0..<parent.data.columns.count {
                    allCells.insert(CellAddress(row: row, col: col))
                }
            }

            parent.selectedCells = allCells
            let anchor = parent.anchorCell ?? CellAddress(row: 0, col: 0)
            parent.anchorCell = anchor
            selectionOrigin = CellAddress(row: 0, col: 0)
            refreshSelectionDisplay()
        }

        // MARK: - Column Sizing

        func autofitFocusedColumn() -> Bool {
            guard let focusedCell = parent.anchorCell,
                  focusedCell.col >= 0,
                  focusedCell.col < parent.data.columns.count,
                  let tv = tableView else {
                return false
            }

            let columnIndex = focusedCell.col + 1
            guard columnIndex > 0, columnIndex < tv.tableColumns.count else { return false }

            let tableColumn = tv.tableColumns[columnIndex]
            let columnName = parent.data.columns[focusedCell.col].name
            let fittedWidth = autofitWidth(forColumn: focusedCell.col, named: columnName, tableColumn: tableColumn)

            tableColumn.width = fittedWidth
            parent.columnWidths[columnName] = fittedWidth
            tv.headerView?.needsDisplay = true
            refreshSelectionDisplay()
            scrollToCell(focusedCell)
            return true
        }

        private func autofitWidth(forColumn column: Int, named columnName: String, tableColumn: NSTableColumn) -> CGFloat {
            let headerWidth = measuredWidth(columnName, font: DriftCellMetrics.headerFont) + headerPaddingWidth()
            var maxWidth = headerWidth

            for row in parent.data.rows {
                let value: String
                if column < row.count {
                    value = row[column] ?? "NULL"
                } else {
                    value = "NULL"
                }

                let width = measuredWidth(value, font: DriftCellMetrics.valueFont)
                    + DriftCellMetrics.horizontalPadding * 2
                    + DriftCellMetrics.autofitExtraPadding
                maxWidth = max(maxWidth, width)
            }

            let roundedWidth = ceil(maxWidth)
            let minimumWidth = max(tableColumn.minWidth, 60)
            return max(minimumWidth, min(roundedWidth, DriftCellMetrics.autofitMaxWidth))
        }

        private func headerPaddingWidth() -> CGFloat {
            if parent.onFilterChange != nil {
                return DriftHeaderMetrics.leftPadding
                    + DriftHeaderMetrics.filterButtonSize
                    + DriftHeaderMetrics.filterButtonTrailing
                    + DriftHeaderMetrics.rightPadding
            }

            return 10
        }

        private func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
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

private enum DriftCellMetrics {
    static let horizontalPadding: CGFloat = 6
    static let autofitExtraPadding: CGFloat = 18
    static let autofitMaxWidth: CGFloat = 960

    static var valueFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    }

    static var valueBoldFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
    }

    static var headerFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
    }
}

// MARK: - Header View

private enum DriftHeaderMetrics {
    static let leftPadding: CGFloat = 9
    static let rightPadding: CGFloat = 7
    static let filterButtonSize: CGFloat = 18
    static let filterButtonTrailing: CGFloat = 5

    static func filterButtonRect(in cellFrame: NSRect) -> NSRect {
        NSRect(
            x: cellFrame.maxX - filterButtonTrailing - filterButtonSize,
            y: cellFrame.midY - filterButtonSize / 2,
            width: filterButtonSize,
            height: filterButtonSize
        )
    }
}

private final class DriftTableHeaderView: NSTableHeaderView {
    weak var coordinator: NSDataGridView.Coordinator?

    override func mouseDown(with event: NSEvent) {
        guard let tableView else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let columnIndex = column(at: point)
        guard columnIndex >= 0, columnIndex < tableView.tableColumns.count else {
            super.mouseDown(with: event)
            return
        }

        let tableColumn = tableView.tableColumns[columnIndex]
        let headerRect = headerRect(ofColumn: columnIndex)
        if tableColumn.identifier.rawValue != "__row",
           DriftHeaderMetrics.filterButtonRect(in: headerRect).contains(point) {
            coordinator?.showFilterPopover(for: tableColumn, relativeTo: headerRect, in: self)
            return
        }

        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let tableView else { return }

        for (index, tableColumn) in tableView.tableColumns.enumerated()
            where tableColumn.identifier.rawValue != "__row" {
            addCursorRect(
                DriftHeaderMetrics.filterButtonRect(in: headerRect(ofColumn: index)),
                cursor: .pointingHand
            )
        }
    }
}

private final class DriftTableHeaderCell: NSTableHeaderCell {
    var hasFilterButton: Bool
    var isFilterActive: Bool

    init(title: String, hasFilterButton: Bool, isFilterActive: Bool = false) {
        self.hasFilterButton = hasFilterButton
        self.isFilterActive = isFilterActive
        super.init(textCell: title)
    }

    required init(coder: NSCoder) {
        self.hasFilterButton = false
        self.isFilterActive = false
        super.init(coder: coder)
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        DriftTableHeaderCell(
            title: stringValue,
            hasFilterButton: hasFilterButton,
            isFilterActive: isFilterActive
        )
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Theme.nsSurface.setFill()
        cellFrame.fill()

        drawTitle(in: cellFrame)
        if hasFilterButton {
            drawFilterButton(in: cellFrame)
        }

        Theme.nsBorderSubtle.setStroke()
        let borderPath = NSBezierPath()
        borderPath.lineWidth = 1
        borderPath.move(to: NSPoint(x: cellFrame.minX, y: cellFrame.maxY - 0.5))
        borderPath.line(to: NSPoint(x: cellFrame.maxX, y: cellFrame.maxY - 0.5))
        borderPath.move(to: NSPoint(x: cellFrame.maxX - 0.5, y: cellFrame.minY))
        borderPath.line(to: NSPoint(x: cellFrame.maxX - 0.5, y: cellFrame.maxY))
        borderPath.stroke()
    }

    private func drawTitle(in cellFrame: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = hasFilterButton ? .left : .center

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: Theme.nsTextSecondary,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .paragraphStyle: paragraph
        ]

        var titleRect = cellFrame
        if hasFilterButton {
            titleRect.origin.x += DriftHeaderMetrics.leftPadding
            titleRect.size.width -= DriftHeaderMetrics.leftPadding
                + DriftHeaderMetrics.filterButtonSize
                + DriftHeaderMetrics.filterButtonTrailing
                + DriftHeaderMetrics.rightPadding
        } else {
            titleRect = titleRect.insetBy(dx: 5, dy: 0)
        }

        let titleSize = (stringValue as NSString).size(withAttributes: attributes)
        titleRect.origin.y = cellFrame.midY - titleSize.height / 2
        titleRect.size.height = titleSize.height + 2
        (stringValue as NSString).draw(in: titleRect, withAttributes: attributes)
    }

    private func drawFilterButton(in cellFrame: NSRect) {
        let buttonRect = DriftHeaderMetrics.filterButtonRect(in: cellFrame)
        let buttonPath = NSBezierPath(roundedRect: buttonRect, xRadius: 4, yRadius: 4)

        (isFilterActive ? Theme.nsAccentMuted : Theme.nsSurfaceHover.withAlphaComponent(0.45)).setFill()
        buttonPath.fill()

        if isFilterActive {
            Theme.nsAccent.withAlphaComponent(0.5).setStroke()
            buttonPath.lineWidth = 1
            buttonPath.stroke()
        }

        let iconColor = isFilterActive ? Theme.nsAccent : Theme.nsTextTertiary
        iconColor.setStroke()

        let midX = buttonRect.midX
        let midY = buttonRect.midY
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineWidth = 1.2

        for (width, offsetY) in [(9.0, 4.0), (6.0, 0.0), (3.0, -4.0)] {
            let halfWidth = CGFloat(width) / 2
            let y = midY + CGFloat(offsetY)
            path.move(to: NSPoint(x: midX - halfWidth, y: y))
            path.line(to: NSPoint(x: midX + halfWidth, y: y))
        }

        path.stroke()
    }
}

private struct ColumnFilterPopoverView: View {
    let columnName: String
    let onChange: (String) -> Void
    @State private var value: String
    @FocusState private var isFocused: Bool

    init(columnName: String, initialValue: String, onChange: @escaping (String) -> Void) {
        self.columnName = columnName
        self.onChange = onChange
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(.caption, weight: .medium))
                .foregroundColor(value.isEmpty ? Theme.textTertiary : Theme.accent)
                .frame(width: 18)

            TextField("Filter \(columnName)", text: $value)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.text)
                .focused($isFocused)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Theme.surface)
                .cornerRadius(Theme.smallRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.smallRadius)
                        .stroke(Theme.border, lineWidth: 1)
                )

            Kbd("F")

            if !value.isEmpty {
                Button {
                    value = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.caption))
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 240)
        .background(Theme.surfaceElevated)
        .onChange(of: value) { _, newValue in
            onChange(newValue)
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}

private struct CellValuePreviewPopoverView: View {
    let columnName: String
    let rowNumber: Int
    let value: String?

    private var displayValue: String {
        value ?? "NULL"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(columnName)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)

                Text("Row \(rowNumber)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)

                Spacer()
            }

            ScrollView {
                Text(displayValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(value == nil ? Theme.textSecondary : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
            .cornerRadius(Theme.smallRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.smallRadius)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
        .padding(12)
        .frame(width: 440, height: 260)
        .background(Theme.surfaceElevated)
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
        label.font = DriftCellMetrics.valueFont
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.drawsBackground = false
        label.isBordered = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        if let textCell = label.cell as? NSTextFieldCell {
            textCell.lineBreakMode = .byTruncatingTail
            textCell.truncatesLastVisibleLine = true
            textCell.usesSingleLineMode = true
        }
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DriftCellMetrics.horizontalPadding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DriftCellMetrics.horizontalPadding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isSelected {
            let color = isFlashing
                ? Theme.nsAccent.withAlphaComponent(0.5)
                : Theme.nsAccent.withAlphaComponent(0.25)
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
        let pointInTable = adjustedPointInTable(for: event, tableView: tv)
        let rowAt = tv.row(at: pointInTable)
        let colAt = tv.column(at: pointInTable)
        if rowAt >= 0, colAt >= 1 {
            coord.extendDrag(to: CellAddress(row: rowAt, col: colAt - 1))
        }
    }

    override func mouseUp(with event: NSEvent) {
        coordinator?.endDrag()
    }

    private func adjustedPointInTable(for event: NSEvent, tableView: NSTableView) -> NSPoint {
        tableView.convert(event.locationInWindow, from: nil)
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
        case 53:
            if isGoHomeShortcut(event), let onCommandEscape = coordinator?.parent.onCommandEscape {
                onCommandEscape()
                return
            }
            if let onEscape = coordinator?.parent.onEscape {
                onEscape()
                return
            }
        case 126: coordinator?.moveSelection(dRow: -1, dCol: 0, shift: shift, jumpToEdge: cmd); return
        case 125: coordinator?.moveSelection(dRow: 1, dCol: 0, shift: shift, jumpToEdge: cmd); return
        case 123: coordinator?.moveSelection(dRow: 0, dCol: -1, shift: shift, jumpToEdge: cmd); return
        case 124: coordinator?.moveSelection(dRow: 0, dCol: 1, shift: shift, jumpToEdge: cmd); return
        case 0:   // A
            if cmd { coordinator?.selectAllCells(); return }
        case 8:   // C
            if cmd { coordinator?.copySelection(); return }
        case 11:  // B
            if isSidebarFocusShortcut(event), let onFocusActiveTableInSidebar = coordinator?.parent.onFocusActiveTableInSidebar {
                onFocusActiveTableInSidebar()
                return
            }
        case 13:  // W
            if isColumnAutofitShortcut(event), coordinator?.autofitFocusedColumn() == true {
                return
            }
        case 3:   // F
            if isFilterShortcut(event), coordinator?.showFilterPopoverForFocusedColumn() == true {
                return
            }
        case 49:  // Space
            if isCellPreviewShortcut(event), coordinator?.showValuePreviewForFocusedCell() == true {
                return
            }
        default: break
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isGoHomeShortcut(event), let onCommandEscape = coordinator?.parent.onCommandEscape {
            onCommandEscape()
            return true
        }
        if isGridNavigationShortcut(event) {
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func isGoHomeShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return modifiers == [.command] && (event.keyCode == 4 || event.keyCode == 53)
    }

    private func isFilterShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers.isEmpty || modifiers == [.shift] else { return false }
        return event.charactersIgnoringModifiers?.lowercased() == "f"
    }

    private func isCellPreviewShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return modifiers.isEmpty && event.charactersIgnoringModifiers == " "
    }

    private func isSidebarFocusShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers.isEmpty || modifiers == [.shift] else { return false }
        return event.charactersIgnoringModifiers?.lowercased() == "b"
    }

    private func isColumnAutofitShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers.isEmpty || modifiers == [.shift] else { return false }
        return event.charactersIgnoringModifiers?.lowercased() == "w"
    }

    private func isGridNavigationShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == [.command] || modifiers == [.command, .shift] else { return false }
        switch event.keyCode {
        case 123, 124, 125, 126:
            return true
        default:
            return false
        }
    }

    override func selectAll(_ sender: Any?) {
        coordinator?.selectAllCells()
    }
}
