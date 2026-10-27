//
//  DataTableViewController.swift
//  Hackintool
//
//  A sortable, searchable table of rows, described by a list of columns.
//

import Cocoa

/// A value a column sorts by.
enum SortKey: Comparable {
	case text(String)
	case number(Double)

	static func < (lhs: SortKey, rhs: SortKey) -> Bool {
		switch (lhs, rhs) {
		case let (.number(a), .number(b)): return a < b
		case let (.text(a), .text(b)): return a.localizedStandardCompare(b) == .orderedAscending
		case (.number, .text): return true
		case (.text, .number): return false
		}
	}
}

struct DataColumn<Row> {
	let identifier: String
	let title: String
	var width: CGFloat = 120
	var minWidth: CGFloat = 40
	var monospaced = false
	var alignment: NSTextAlignment = .natural
	let text: (Row) -> String
	/// Defaults to sorting by the displayed text.
	var sortKey: ((Row) -> SortKey)?
	/// Makes the column editable; called with the row and the new text.
	var onEdit: ((Row, String) -> Void)?
	/// An icon shown before the text.
	var image: ((Row) -> NSImage?)?
	/// A custom cell (a level indicator, a button...) instead of text. The text is still used for sorting, search and copying.
	var customView: ((Row) -> NSView)?

	/// - Parameter title: an English column title, localized for display.
	init(_ identifier: String, _ title: String, width: CGFloat = 120, monospaced: Bool = false,
	     alignment: NSTextAlignment = .natural, sortKey: ((Row) -> SortKey)? = nil,
	     onEdit: ((Row, String) -> Void)? = nil, text: @escaping (Row) -> String) {
		self.identifier = identifier
		self.title = L(title)
		self.width = width
		self.monospaced = monospaced
		self.alignment = alignment
		self.sortKey = sortKey
		self.onEdit = onEdit
		self.text = text
	}

	/// A column of numbers shown in hex and sorted numerically.
	static func hex(_ identifier: String, _ title: String, width: CGFloat = 80, digits: Int = 4, _ value: @escaping (Row) -> UInt32) -> DataColumn {
		return DataColumn(identifier, title, width: width, monospaced: true,
		                  sortKey: { .number(Double(value($0))) },
		                  text: { String(format: "0x%0\(digits)X", value($0)) })
	}
}

class DataTableViewController<Row>: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation, SectionContent {
	let tableView = NSTableView()
	let columns: [DataColumn<Row>]

	private(set) var rows: [Row] = []
	private var displayedRows: [Row] = []
	private var filterText = ""

	var onSelectionChange: (([Row]) -> Void)?
	var onDoubleClick: ((Row) -> Void)?
	/// Called when the toolbar refresh button is pressed; nil disables refresh.
	var onRefresh: (() -> Void)?
	/// Optional row tint, e.g. green for an active USB port.
	var rowColor: ((Row) -> NSColor?)?
	/// Shown over the table when it has no rows.
	var emptyState: EmptyState? {
		didSet { updateEmptyState() }
	}
	private let emptyStateView = EmptyStateView()
	/// Extra context-menu items, appended after Copy.
	var contextMenuItems: [NSMenuItem] = [] {
		didSet {
			if isViewLoaded {
				tableView.menu = makeContextMenu()
			}
		}
	}

	init(columns: [DataColumn<Row>]) {
		self.columns = columns
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	override func loadView() {
		for column in columns {
			let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.identifier))
			tableColumn.title = column.title
			tableColumn.width = column.width
			tableColumn.minWidth = column.minWidth
			tableColumn.headerCell.alignment = column.alignment
			tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.identifier, ascending: true)
			tableView.addTableColumn(tableColumn)
		}
		tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		tableView.allowsMultipleSelection = true
		tableView.usesAlternatingRowBackgroundColors = true
		tableView.dataSource = self
		tableView.delegate = self
		tableView.target = self
		tableView.doubleAction = #selector(doubleClicked(_:))
		tableView.menu = makeContextMenu()
		if #available(macOS 11.0, *) {
			tableView.style = .fullWidth
		}
		let container = NSView()
		container.addPinnedSubview(ScrollingTable.wrap(tableView))
		// Below the header row, so the column titles stay visible.
		emptyStateView.isHidden = true
		container.addPinnedSubview(emptyStateView, insets: NSEdgeInsets(top: 28, left: 0, bottom: 0, right: 0))
		view = container
	}

	func setRows(_ rows: [Row]) {
		self.rows = rows
		reload()
	}

	/// Rows in display order (filtered and sorted).
	var visibleRows: [Row] {
		return displayedRows
	}

	var selectedRows: [Row] {
		return tableView.selectedRowIndexes.compactMap { displayedRows.indices.contains($0) ? displayedRows[$0] : nil }
	}

	/// The clicked row for context menus, falling back to the selection.
	var targetRows: [Row] {
		let clicked = tableView.clickedRow
		if clicked >= 0, !tableView.selectedRowIndexes.contains(clicked), displayedRows.indices.contains(clicked) {
			return [displayedRows[clicked]]
		}
		return selectedRows
	}

	func reload() {
		var filtered = rows
		if !filterText.isEmpty {
			filtered = rows.filter { row in
				columns.contains { $0.text(row).localizedCaseInsensitiveContains(filterText) }
			}
		}
		if let descriptor = tableView.sortDescriptors.first, let key = descriptor.key,
		   let column = columns.first(where: { $0.identifier == key }) {
			let sortKey = column.sortKey ?? { .text(column.text($0)) }
			filtered.sort { descriptor.ascending ? sortKey($0) < sortKey($1) : sortKey($1) < sortKey($0) }
		}
		displayedRows = filtered
		tableView.reloadData()
		updateEmptyState()
	}

	private func updateEmptyState() {
		guard isViewLoaded else { return }
		let state = !displayedRows.isEmpty ? nil
			: !rows.isEmpty ? EmptyState(.search, "No Matches")
			: emptyState
		if let state = state {
			emptyStateView.show(state)
		}
		emptyStateView.isHidden = state == nil
		// Stripes under a message look like a table that failed to load.
		tableView.usesAlternatingRowBackgroundColors = state == nil
	}

	// MARK: SectionContent

	var canRefresh: Bool { return onRefresh != nil }
	func refresh() { onRefresh?() }
	var searchPlaceholder: String? { return L("Search") }

	func search(_ text: String) {
		filterText = text
		reload()
	}

	// MARK: Data source and delegate

	func numberOfRows(in tableView: NSTableView) -> Int {
		return displayedRows.count
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let tableColumn = tableColumn,
		      let column = columns.first(where: { $0.identifier == tableColumn.identifier.rawValue }) else { return nil }
		if let customView = column.customView {
			return customView(displayedRows[row])
		}
		let cell = column.image != nil
			? ImageTextCell.make(in: tableView, identifier: tableColumn.identifier)
			: TextCell.make(in: tableView, identifier: tableColumn.identifier)
		cell.imageView?.image = column.image?(displayedRows[row])
		let value = column.text(displayedRows[row])
		// "???" marks a name that couldn't be looked up.
		let isUnknown = value == "???" || value.hasSuffix(" ???")
		cell.textField?.stringValue = isUnknown ? value.replacingOccurrences(of: "???", with: L("Unknown")) : value
		cell.textField?.textColor = isUnknown ? .tertiaryLabelColor : .labelColor
		cell.textField?.alignment = column.alignment
		cell.textField?.font = column.monospaced
			? .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
			: .systemFont(ofSize: NSFont.systemFontSize)
		cell.toolTip = value
		if let textField = cell.textField {
			textField.isEditable = column.onEdit != nil
			textField.target = column.onEdit != nil ? self : nil
			textField.action = column.onEdit != nil ? #selector(cellEdited(_:)) : nil
			textField.identifier = tableColumn.identifier
		}
		return cell
	}

	@objc private func cellEdited(_ sender: NSTextField) {
		let row = tableView.row(for: sender)
		guard displayedRows.indices.contains(row), let identifier = sender.identifier?.rawValue,
		      let column = columns.first(where: { $0.identifier == identifier }),
		      sender.stringValue != column.text(displayedRows[row]) else { return }
		column.onEdit?(displayedRows[row], sender.stringValue)
	}

	func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
		guard let rowColor = rowColor else { return }
		rowView.backgroundColor = rowColor(displayedRows[row])?.withAlphaComponent(0.25) ?? .clear
	}

	func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
		reload()
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		onSelectionChange?(selectedRows)
	}

	@objc private func doubleClicked(_ sender: Any?) {
		let row = tableView.clickedRow
		guard displayedRows.indices.contains(row) else { return }
		onDoubleClick?(displayedRows[row])
	}

	// MARK: Copying

	/// Copies the selected rows as tab-separated text, with a header line.
	@objc func copy(_ sender: Any?) {
		let rows = targetRows
		guard !rows.isEmpty else { return }
		let header = columns.map { $0.title }.joined(separator: "\t")
		let lines = rows.map { row in columns.map { $0.text(row) }.joined(separator: "\t") }
		Pasteboard.copy(([header] + lines).joined(separator: "\n"))
	}

	private func makeContextMenu() -> NSMenu {
		// A menu item can only belong to one menu at a time.
		tableView.menu?.removeAllItems()
		let menu = NSMenu()
		menu.addItem(withTitle: L("Copy"), action: #selector(copy(_:)), keyEquivalent: "").target = self
		if !contextMenuItems.isEmpty {
			menu.addItem(.separator())
			contextMenuItems.forEach { menu.addItem($0) }
		}
		return menu
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		if menuItem.action == #selector(copy(_:)) {
			return !targetRows.isEmpty
		}
		return true
	}
}

extension DataColumn {
	/// Adds an icon before the column's text.
	func with(image: @escaping (Row) -> NSImage?) -> DataColumn {
		var column = self
		column.image = image
		return column
	}

	/// Replaces the column's cell with a custom view.
	func with(customView: @escaping (Row) -> NSView) -> DataColumn {
		var column = self
		column.customView = customView
		return column
	}
}
