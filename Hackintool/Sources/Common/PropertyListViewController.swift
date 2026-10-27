//
//  PropertyListViewController.swift
//  Hackintool
//
//  A two-column Name / Value list, optionally grouped under headers.
//  Supports search, ⌘C and a Copy / Copy Value context menu.
//

import Cocoa

struct PropertyItem {
	var name: String
	var value: String

	/// - Parameter name: an English label, localized for display.
	init(_ name: String, _ value: String?) {
		self.name = L(name)
		self.value = value ?? "???"
	}
}

struct PropertyGroup {
	var title: String
	var items: [PropertyItem]

	init(_ title: String, _ items: [PropertyItem]) {
		self.title = L(title)
		self.items = items
	}
}

class PropertyListViewController: NSViewController, SectionContent {
	/// NSOutlineView tracks items by identity, so rows are wrapped in objects.
	private final class Node: NSObject {
		let title: String
		let value: String
		let children: [Node]
		let isGroup: Bool

		init(group: PropertyGroup, filter: String) {
			title = group.title
			value = ""
			isGroup = true
			children = group.items
				.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.value.localizedCaseInsensitiveContains(filter) }
				.map { Node(item: $0) }
		}

		init(item: PropertyItem) {
			title = item.name
			value = item.value
			isGroup = false
			children = []
		}
	}

	let outlineView = NSOutlineView()
	private var groups: [PropertyGroup] = []
	private var nodes: [Node] = []
	private var filterText = ""
	private let showsGroupHeaders: Bool

	/// Called when the toolbar refresh button is pressed; nil disables refresh.
	var onRefresh: (() -> Void)?

	init(showsGroupHeaders: Bool = true) {
		self.showsGroupHeaders = showsGroupHeaders
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	override func loadView() {
		let nameColumn = NSTableColumn(identifier: .name)
		nameColumn.title = L("Name")
		nameColumn.width = 220
		nameColumn.minWidth = 120
		let valueColumn = NSTableColumn(identifier: .value)
		valueColumn.title = L("Value")
		valueColumn.minWidth = 160

		outlineView.addTableColumn(nameColumn)
		outlineView.addTableColumn(valueColumn)
		outlineView.outlineTableColumn = nameColumn
		outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		outlineView.allowsMultipleSelection = true
		outlineView.floatsGroupRows = true
		outlineView.indentationPerLevel = 0
		outlineView.usesAlternatingRowBackgroundColors = !showsGroupHeaders
		outlineView.dataSource = self
		outlineView.delegate = self
		outlineView.menu = makeContextMenu()
		if #available(macOS 11.0, *) {
			outlineView.style = .inset
		}

		view = ScrollingTable.wrap(outlineView)
	}

	func setGroups(_ groups: [PropertyGroup]) {
		self.groups = groups
		reload()
	}

	func setItems(_ items: [PropertyItem]) {
		setGroups([PropertyGroup("", items)])
	}

	private func reload() {
		nodes = groups.map { Node(group: $0, filter: filterText) }.filter { !$0.children.isEmpty }
		// No stripes on an empty list; they look like a table that failed to load.
		outlineView.usesAlternatingRowBackgroundColors = !showsGroupHeaders && !nodes.isEmpty
		outlineView.reloadData()
		outlineView.expandItem(nil, expandChildren: true)
	}

	private var displaysGroupHeaders: Bool {
		return showsGroupHeaders && groups.count > 0
	}

	// MARK: SectionContent

	var canRefresh: Bool { return onRefresh != nil }
	func refresh() { onRefresh?() }
	var searchPlaceholder: String? { return L("Search") }

	func search(_ text: String) {
		filterText = text
		reload()
	}

	// MARK: Copying

	private var selectedNodes: [Node] {
		let rows = outlineView.selectedRowIndexes.isEmpty && outlineView.clickedRow >= 0
			? IndexSet(integer: outlineView.clickedRow)
			: outlineView.selectedRowIndexes
		return rows.compactMap { outlineView.item(atRow: $0) as? Node }.filter { !$0.isGroup }
	}

	@objc func copy(_ sender: Any?) {
		Pasteboard.copy(selectedNodes.map { "\($0.title): \($0.value)" }.joined(separator: "\n"))
	}

	@objc func copyValue(_ sender: Any?) {
		Pasteboard.copy(selectedNodes.map { $0.value }.joined(separator: "\n"))
	}

	private func makeContextMenu() -> NSMenu {
		let menu = NSMenu()
		menu.addItem(withTitle: L("Copy"), action: #selector(copy(_:)), keyEquivalent: "").target = self
		menu.addItem(withTitle: L("Copy Value"), action: #selector(copyValue(_:)), keyEquivalent: "").target = self
		return menu
	}
}

extension PropertyListViewController: NSMenuItemValidation {
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		return !selectedNodes.isEmpty
	}
}

extension PropertyListViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		guard let node = item as? Node else {
			return displaysGroupHeaders ? nodes.count : nodes.first?.children.count ?? 0
		}
		return node.children.count
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		guard let node = item as? Node else {
			return displaysGroupHeaders ? nodes[index] : nodes[0].children[index]
		}
		return node.children[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		return (item as? Node)?.isGroup ?? false
	}

	func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
		return (item as? Node)?.isGroup ?? false
	}

	func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
		return false
	}

	func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
		return !((item as? Node)?.isGroup ?? true)
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? Node else { return nil }
		if node.isGroup {
			let cell = TextCell.make(in: outlineView, identifier: .groupCell)
			cell.textField?.stringValue = node.title
			cell.textField?.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
			return cell
		}
		let isValue = tableColumn?.identifier == .value
		let cell = TextCell.make(in: outlineView, identifier: isValue ? .valueCell : .nameCell)
		let isUnknown = isValue && node.value == "???"
		cell.textField?.stringValue = isValue ? node.value.replacingOccurrences(of: "???", with: L("Unknown")) : node.title
		cell.textField?.textColor = isUnknown ? .tertiaryLabelColor : isValue ? .labelColor : .secondaryLabelColor
		cell.textField?.isSelectable = isValue
		cell.toolTip = isValue ? node.value : nil
		return cell
	}
}

extension NSUserInterfaceItemIdentifier {
	static let name = NSUserInterfaceItemIdentifier("Name")
	static let value = NSUserInterfaceItemIdentifier("Value")
	static let nameCell = NSUserInterfaceItemIdentifier("NameCell")
	static let valueCell = NSUserInterfaceItemIdentifier("ValueCell")
	static let groupCell = NSUserInterfaceItemIdentifier("GroupCell")
}
