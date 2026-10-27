//
//  PropertyListEditor.swift
//  Hackintool
//
//  A Key / Type / Value property list editor like Xcode's, with undo, copy and paste
//  (compatible with Xcode's), drag and drop, and a read-only mode.
//
//  Swift port of LNPropertyListEditor by Leo Natan (https://github.com/LeoNatan/LNPropertyListEditor).
//  Copyright © 2018-2021 Leo Natan. Released under the MIT License.
//  Data values are edited as hex in place, rather than in HexFiend.
//

import Cocoa

enum PropertyListNodeChange {
	case insert, delete, move, update
}

/// Every method is optional: by default everything can be edited.
protocol PropertyListEditorDelegate: AnyObject {
	func propertyListEditor(_ editor: PropertyListEditor, willChange node: PropertyListNode, change: PropertyListNodeChange, previousKey: String?)
	func propertyListEditor(_ editor: PropertyListEditor, didChange node: PropertyListNode, change: PropertyListNodeChange, previousKey: String?)
	func propertyListEditor(_ editor: PropertyListEditor, canEditKeyOf node: PropertyListNode) -> Bool
	func propertyListEditor(_ editor: PropertyListEditor, canEditTypeOf node: PropertyListNode) -> Bool
	func propertyListEditor(_ editor: PropertyListEditor, canEditValueOf node: PropertyListNode) -> Bool
	func propertyListEditor(_ editor: PropertyListEditor, canDelete node: PropertyListNode) -> Bool
	func propertyListEditor(_ editor: PropertyListEditor, canAddChildIn node: PropertyListNode) -> Bool
	func propertyListEditor(_ editor: PropertyListEditor, canReorderChildrenOf node: PropertyListNode) -> Bool
	func propertyListEditor(_ editor: PropertyListEditor, canPaste pasted: PropertyListNode, asChildOf node: PropertyListNode) -> Bool
	func propertyListEditor(_ editor: PropertyListEditor, canMove node: PropertyListNode, to parent: PropertyListNode, at index: Int) -> Bool
	/// A property list object or a PropertyListNode for a new child; nil adds an empty string.
	func propertyListEditor(_ editor: PropertyListEditor, defaultPropertyListForChildIn node: PropertyListNode) -> Any?
}

extension PropertyListEditorDelegate {
	func propertyListEditor(_ editor: PropertyListEditor, willChange node: PropertyListNode, change: PropertyListNodeChange, previousKey: String?) {}
	func propertyListEditor(_ editor: PropertyListEditor, didChange node: PropertyListNode, change: PropertyListNodeChange, previousKey: String?) {}
	func propertyListEditor(_ editor: PropertyListEditor, canEditKeyOf node: PropertyListNode) -> Bool { return true }
	func propertyListEditor(_ editor: PropertyListEditor, canEditTypeOf node: PropertyListNode) -> Bool { return true }
	func propertyListEditor(_ editor: PropertyListEditor, canEditValueOf node: PropertyListNode) -> Bool { return true }
	func propertyListEditor(_ editor: PropertyListEditor, canDelete node: PropertyListNode) -> Bool { return true }
	func propertyListEditor(_ editor: PropertyListEditor, canAddChildIn node: PropertyListNode) -> Bool { return true }
	func propertyListEditor(_ editor: PropertyListEditor, canReorderChildrenOf node: PropertyListNode) -> Bool { return true }
	func propertyListEditor(_ editor: PropertyListEditor, canPaste pasted: PropertyListNode, asChildOf node: PropertyListNode) -> Bool { return true }
	func propertyListEditor(_ editor: PropertyListEditor, canMove node: PropertyListNode, to parent: PropertyListNode, at index: Int) -> Bool { return false }
	func propertyListEditor(_ editor: PropertyListEditor, defaultPropertyListForChildIn node: PropertyListNode) -> Any? { return nil }
}

/// Shows values differently from how they're stored, e.g. a number as a name.
protocol PropertyListEditorDataTransformer: AnyObject {
	func propertyListEditor(_ editor: PropertyListEditor, displayNameFor node: PropertyListNode) -> String?
	/// A property list object to show instead of the node's value.
	func propertyListEditor(_ editor: PropertyListEditor, displayValueFor node: PropertyListNode) -> Any?
	/// Converts an edited display value back to what's stored.
	func propertyListEditor(_ editor: PropertyListEditor, storageValueFor node: PropertyListNode, displayValue: Any) -> Any?
}

extension PropertyListEditorDataTransformer {
	func propertyListEditor(_ editor: PropertyListEditor, displayNameFor node: PropertyListNode) -> String? { return nil }
	func propertyListEditor(_ editor: PropertyListEditor, displayValueFor node: PropertyListNode) -> Any? { return nil }
	func propertyListEditor(_ editor: PropertyListEditor, storageValueFor node: PropertyListNode, displayValue: Any) -> Any? { return nil }
}

final class PropertyListEditor: NSView {
	let outlineView = PropertyListOutlineView()
	let scrollView: NSScrollView
	private let keyColumn = NSTableColumn(identifier: .plistKeyColumn)
	private let typeColumn = NSTableColumn(identifier: .plistTypeColumn)
	private let valueColumn = NSTableColumn(identifier: .plistValueColumn)
	private let keySortPrototype = NSSortDescriptor(key: "sortKey", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
	private let typeSortPrototype = NSSortDescriptor(key: "sortType", ascending: true, selector: #selector(NSNumber.compare(_:)))
	private let valueSortPrototype = NSSortDescriptor(key: "sortValue", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
	private let contextMenu = NSMenu()
	private let editorUndoManager = UndoManager()

	weak var delegate: PropertyListEditorDelegate?
	weak var dataTransformer: PropertyListEditorDataTransformer?

	/// When false nothing can be changed, though rows can still be selected, copied and dragged out.
	var isEditable = true {
		didSet { outlineView.reloadData() }
	}

	private(set) var rootNode: PropertyListNode?

	override init(frame frameRect: NSRect) {
		scrollView = ScrollingTable.wrap(outlineView)
		super.init(frame: frameRect)
		commonInit()
	}

	required init?(coder: NSCoder) {
		scrollView = ScrollingTable.wrap(outlineView)
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		keyColumn.title = L("Key")
		keyColumn.width = 220
		keyColumn.minWidth = 120
		keyColumn.maxWidth = 1000
		typeColumn.title = L("Type")
		typeColumn.width = 84
		typeColumn.minWidth = 84
		typeColumn.maxWidth = 84
		valueColumn.title = L("Value")
		valueColumn.width = 400
		valueColumn.minWidth = 160
		valueColumn.maxWidth = 10_000_000
		[keyColumn, typeColumn, valueColumn].forEach(outlineView.addTableColumn)
		outlineView.outlineTableColumn = keyColumn
		outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		outlineView.allowsColumnReordering = false
		outlineView.allowsMultipleSelection = false
		outlineView.allowsExpansionToolTips = true
		outlineView.usesAlternatingRowBackgroundColors = true
		outlineView.indentationPerLevel = 14
		outlineView.rowSizeStyle = .small
		if #available(macOS 11.0, *) {
			outlineView.style = .inset
		}
		outlineView.dataSource = self
		outlineView.delegate = self
		outlineView.target = self
		outlineView.action = #selector(outlineViewClicked(_:))
		outlineView.doubleAction = #selector(outlineViewDoubleClicked(_:))
		outlineView.registerForDraggedTypes([.propertyListNode])
		outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
		buildContextMenu()
		allowsColumnSorting = false

		editorUndoManager.groupsByEvent = false
		addPinnedSubview(scrollView)
	}

	private func buildContextMenu() {
		func add(_ title: String, _ action: Selector, to menu: NSMenu, tag: Int = 0) {
			let item = menu.addItem(withTitle: L(title), action: action, keyEquivalent: "")
			item.target = self
			item.tag = tag
		}
		add("Cut", #selector(cut(_:)), to: contextMenu)
		add("Copy", #selector(copy(_:)), to: contextMenu)
		add("Copy Key", #selector(copyKey(_:)), to: contextMenu)
		add("Copy Value", #selector(copyValue(_:)), to: contextMenu)
		add("Paste", #selector(paste(_:)), to: contextMenu)
		contextMenu.addItem(.separator())
		let types = NSMenu()
		for kind in PropertyListNode.Kind.menuOrder {
			if let kind = kind {
				add(kind.name, #selector(convertType(_:)), to: types, tag: kind.rawValue)
			} else {
				types.addItem(.separator())
			}
		}
		contextMenu.addItem(withTitle: L("Value Type"), action: nil, keyEquivalent: "").submenu = types
		contextMenu.addItem(.separator())
		add("Add Item", #selector(add(_:)), to: contextMenu)
	}

	// MARK: Configuration

	var isTypeColumnHidden: Bool {
		get { return typeColumn.isHidden }
		set { typeColumn.isHidden = newValue }
	}

	/// Clicking a column header sorts the model (when the delegate allows it).
	var allowsColumnSorting = false {
		didSet {
			keyColumn.sortDescriptorPrototype = allowsColumnSorting ? keySortPrototype : nil
			typeColumn.sortDescriptorPrototype = allowsColumnSorting ? typeSortPrototype : nil
			valueColumn.sortDescriptorPrototype = allowsColumnSorting ? valueSortPrototype : nil
		}
	}

	/// The edited property list as Foundation objects. Dictionaries lose their key order;
	/// use `rootNode` or `xmlString` to keep it.
	var propertyListObject: Any? {
		get { return rootNode?.propertyListObject }
		set { setRootNode(newValue.flatMap { PropertyListNode(propertyList: $0) }) }
	}

	/// The edited property list as XML, in the editor's order.
	var xmlString: String? {
		return rootNode?.xmlString
	}

	func setRootNode(_ node: PropertyListNode?) {
		rootNode = node
		editorUndoManager.removeAllActions()
		if allowsColumnSorting {
			let descriptors = [keySortPrototype]
			outlineView.sortDescriptors = descriptors
			sortRootNode(using: descriptors)
		}
		outlineView.reloadData()
		outlineView.menu = node == nil ? nil : contextMenu
	}

	override var undoManager: UndoManager? {
		return editorUndoManager
	}

	// MARK: Expanding and selecting

	private func outlineItem(_ node: PropertyListNode?) -> PropertyListNode? {
		return node === rootNode ? nil : node
	}

	func reload(_ node: PropertyListNode?, reloadChildren: Bool) {
		outlineView.reloadItem(outlineItem(node), reloadChildren: reloadChildren)
	}

	func expand(_ node: PropertyListNode?, expandChildren: Bool) {
		outlineView.expandItem(outlineItem(node), expandChildren: expandChildren)
	}

	func collapse(_ node: PropertyListNode?, collapseChildren: Bool) {
		outlineView.collapseItem(outlineItem(node), collapseChildren: collapseChildren)
	}

	var selectedNode: PropertyListNode? {
		return outlineView.selectedRow < 0 ? nil : outlineView.item(atRow: outlineView.selectedRow) as? PropertyListNode
	}

	func selectRow(for node: PropertyListNode) {
		let row = outlineView.row(forItem: node)
		if row >= 0 {
			outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		}
	}

	func scrollRowToVisible(for node: PropertyListNode) {
		let row = outlineView.row(forItem: node)
		if row >= 0 {
			outlineView.scrollRowToVisible(row)
		}
	}

	// MARK: Permissions

	private func canEditKey(of node: PropertyListNode) -> Bool {
		return isEditable && (delegate?.propertyListEditor(self, canEditKeyOf: node) ?? true)
	}

	private func canEditType(of node: PropertyListNode) -> Bool {
		return isEditable && (delegate?.propertyListEditor(self, canEditTypeOf: node) ?? true)
	}

	private func canEditValue(of node: PropertyListNode) -> Bool {
		return isEditable && (delegate?.propertyListEditor(self, canEditValueOf: node) ?? true)
	}

	func canDelete(_ node: PropertyListNode) -> Bool {
		return isEditable && (delegate?.propertyListEditor(self, canDelete: node) ?? true)
	}

	private func canAddChild(in node: PropertyListNode) -> Bool {
		return isEditable && (delegate?.propertyListEditor(self, canAddChildIn: node) ?? true)
	}

	/// Where a new item goes when added at this row: inside it if it's expanded, otherwise beside it.
	private func insertionParent(for node: PropertyListNode?) -> PropertyListNode? {
		if let node = node, outlineView.isItemExpanded(node) {
			return node
		}
		return node?.parent ?? rootNode
	}

	func canInsert(at node: PropertyListNode?) -> Bool {
		guard let parent = insertionParent(for: node) else { return false }
		return canAddChild(in: parent)
	}

	private func canPaste(_ pasted: PropertyListNode, at node: PropertyListNode?) -> Bool {
		guard let parent = insertionParent(for: node) else { return false }
		return canAddChild(in: parent) && (delegate?.propertyListEditor(self, canPaste: pasted, asChildOf: parent) ?? true)
	}

	// MARK: Changing nodes (undoable)

	private func notifyWill(_ node: PropertyListNode, _ change: PropertyListNodeChange, previousKey: String? = nil) {
		delegate?.propertyListEditor(self, willChange: node, change: change, previousKey: previousKey)
	}

	private func notifyDid(_ node: PropertyListNode, _ change: PropertyListNodeChange, previousKey: String? = nil) {
		delegate?.propertyListEditor(self, didChange: node, change: change, previousKey: previousKey)
	}

	private func registerUndo(_ handler: @escaping (PropertyListEditor) -> Void) {
		editorUndoManager.beginUndoGrouping()
		editorUndoManager.registerUndo(withTarget: self, handler: handler)
		editorUndoManager.endUndoGrouping()
	}

	private func updateKey(_ key: String, of node: PropertyListNode) {
		guard node.key != key else { return }
		let oldKey = node.key
		node.key = key
		notifyWill(node, .update, previousKey: oldKey)
		outlineView.reloadItem(node)
		registerUndo { $0.updateKey(oldKey ?? "", of: node) }
		notifyDid(node, .update, previousKey: oldKey)
	}

	private func setType(_ type: PropertyListNode.Kind, children: [PropertyListNode]?, value: Any?, for node: PropertyListNode) {
		let oldType = node.type
		let oldValue = node.value
		let oldChildren = node.children
		node.type = type
		node.value = value
		node.children = children
		children?.forEach { $0.parent = node }
		notifyWill(node, .update, previousKey: node.key)
		outlineView.reloadItem(outlineItem(node), reloadChildren: true)
		registerUndo { $0.setType(oldType, children: oldChildren, value: oldValue, for: node) }
		notifyDid(node, .update, previousKey: node.key)
	}

	private func convert(_ node: PropertyListNode, to type: PropertyListNode.Kind) {
		guard node.type != type else { return }
		var value = type.defaultValue
		// Keep what can be kept: numbers ↔ strings ↔ booleans.
		if let text = node.type.isContainer ? nil : node.displayValue as String?, !text.isEmpty,
		   let converted = PropertyListNode.value(from: text, type: type) {
			value = converted
		}
		setType(type, children: type.isContainer ? [] : nil, value: value, for: node)
	}

	private func updateValue(_ value: Any, of node: PropertyListNode, reloadItem: Bool) {
		var stored = value
		if !node.type.isContainer, let transformed = dataTransformer?.propertyListEditor(self, storageValueFor: node, displayValue: value) {
			stored = transformed
		}
		guard PropertyListNode.Kind(of: stored) == node.type else {
			assertionFailure("Value type \(PropertyListNode.Kind(of: stored).name) does not match node type \(node.type.name).")
			return
		}
		if let current = node.value as? NSObject, current.isEqual(stored) {
			return
		}
		let oldValue = node.value
		node.value = stored
		notifyWill(node, .update, previousKey: node.key)
		if reloadItem {
			outlineView.reloadItem(node)
		}
		registerUndo { editor in
			if let oldValue = oldValue {
				editor.updateValue(oldValue, of: node, reloadItem: true)
			}
		}
		notifyDid(node, .update, previousKey: node.key)
	}

	private func keyExists(_ key: String, in parent: PropertyListNode?, excluding node: PropertyListNode) -> Bool {
		return parent?.children?.contains { $0.key == key && $0 !== node } ?? false
	}

	private func insert(_ node: PropertyListNode, in parent: PropertyListNode, at index: Int, notify: Bool, undoable: Bool) {
		node.parent = parent
		if parent.type == .dictionary {
			let originalKey = node.key ?? L("New item")
			node.key = originalKey
			var count = 2
			while keyExists(node.key ?? "", in: parent, excluding: node) {
				node.key = "\(originalKey) - \(count)"
				count += 1
			}
		}
		if parent.children == nil {
			parent.children = []
		}
		let index = index < 0 ? parent.children!.count : min(index, parent.children!.count)
		if notify {
			notifyWill(parent, .update)
			notifyWill(node, .insert)
		}
		outlineView.beginUpdates()
		parent.children!.insert(node, at: index)
		outlineView.insertItems(at: IndexSet(integer: index), inParent: outlineItem(parent), withAnimation: [])
		outlineView.endUpdates()
		reload(parent, reloadChildren: true)
		let row = outlineView.row(forItem: node)
		if row >= 0 {
			outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		}
		if undoable {
			registerUndo { $0.delete(node, notify: notify, undoable: undoable) }
		}
		if notify {
			notifyDid(node, .insert)
			notifyDid(parent, .update)
		}
	}

	private func insert(_ node: PropertyListNode, forSender sender: Any?) {
		var row = self.row(for: sender, beep: false)
		if row < 0 {
			row = outlineView.numberOfRows - 1
		}
		let clicked = row >= 0 ? outlineView.item(atRow: row) as? PropertyListNode : nil
		guard let parent = insertionParent(for: clicked) else { return }
		let index = parent === clicked ? 0 : clicked.flatMap { parent.children?.firstIndex(of: $0) }.map { $0 + 1 } ?? -1
		insert(node, in: parent, at: index, notify: true, undoable: true)
	}

	private func delete(_ node: PropertyListNode, notify: Bool, undoable: Bool) {
		// Not part of the tree (already deleted).
		guard let parent = node.parent, let index = parent.children?.firstIndex(of: node) else { return }
		guard canDelete(node) || !notify else {
			NSSound.beep()
			return
		}
		var selectedRow = outlineView.selectedRow
		if notify {
			notifyWill(parent, .update)
			notifyWill(node, .delete)
		}
		outlineView.beginUpdates()
		parent.children!.remove(at: index)
		node.parent = nil
		outlineView.removeItems(at: IndexSet(integer: index), inParent: outlineItem(parent), withAnimation: [])
		outlineView.endUpdates()
		reload(parent, reloadChildren: true)
		if undoable {
			registerUndo { $0.insert(node, in: parent, at: index, notify: notify, undoable: undoable) }
		}
		if selectedRow >= 0 {
			selectedRow = min(max(selectedRow - 1, 0), outlineView.numberOfRows - 1)
			outlineView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
		}
		if notify {
			notifyDid(node, .delete)
			notifyDid(parent, .update)
		}
	}

	private func move(_ node: PropertyListNode, into parent: PropertyListNode, at index: Int, adjust: Bool) {
		guard let oldParent = node.parent, let oldIndex = oldParent.children?.firstIndex(of: node) else { return }
		var index = index
		if adjust && oldParent === parent {
			if oldIndex < index {
				index -= 1
			}
			if oldIndex == index {
				return
			}
		}
		notifyWill(oldParent, .update)
		if oldParent !== parent {
			notifyWill(parent, .update)
		}
		notifyWill(node, .move)
		registerUndo { $0.move(node, into: oldParent, at: oldIndex, adjust: false) }
		delete(node, notify: false, undoable: false)
		insert(node, in: parent, at: index, notify: false, undoable: false)
		notifyDid(node, .move)
		if oldParent !== parent {
			notifyDid(parent, .update)
		}
		notifyDid(oldParent, .update)
	}

	// MARK: Sorting

	private func sortRootNode(using descriptors: [NSSortDescriptor]) {
		guard allowsColumnSorting, let root = rootNode else { return }
		sort(root, using: descriptors)
	}

	private func sort(_ node: PropertyListNode, using descriptors: [NSSortDescriptor]) {
		guard node.type.isContainer, delegate?.propertyListEditor(self, canReorderChildrenOf: node) ?? true else { return }
		notifyWill(node, .update)
		// Array items have no keys, so a key sort leaves them in order.
		let applicable = node.type == .array ? descriptors.filter { $0.key != keySortPrototype.key } : descriptors
		if !applicable.isEmpty, let children = node.children {
			node.children = (children as NSArray).sortedArray(using: applicable) as? [PropertyListNode]
		}
		node.children?.forEach { sort($0, using: descriptors) }
		notifyDid(node, .update)
	}

	// MARK: Actions

	/// The row an action applies to: the control's row, the clicked row, or the selection.
	private func row(for sender: Any?, beep: Bool) -> Int {
		var row = -1
		if let view = sender as? NSView {
			row = outlineView.row(for: view)
		}
		if row < 0 {
			row = outlineView.clickedRow
		}
		if row < 0 {
			row = outlineView.selectedRow
		}
		if row < 0 && beep {
			NSSound.beep()
		}
		return row
	}

	private func node(for sender: Any?, beep: Bool) -> PropertyListNode? {
		let row = self.row(for: sender, beep: beep)
		return row < 0 ? nil : outlineView.item(atRow: row) as? PropertyListNode
	}

	/// Ends any edit in progress so the action sees its result.
	private func endEditing() {
		if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: self) {
			window?.makeFirstResponder(outlineView)
		}
	}

	@objc func add(_ sender: Any?) {
		let node = self.node(for: sender, beep: false)
		guard canInsert(at: node), let parent = insertionParent(for: node) else {
			NSSound.beep()
			return
		}
		let template = delegate?.propertyListEditor(self, defaultPropertyListForChildIn: parent) ?? ""
		let inserted = (template as? PropertyListNode)?.deepCopy() ?? PropertyListNode(propertyList: template) ?? PropertyListNode(type: .string, value: "")
		insert(inserted, forSender: sender)
	}

	@objc func cut(_ sender: Any?) {
		copy(sender)
		delete(sender)
	}

	@objc func copy(_ sender: Any?) {
		endEditing()
		guard let node = node(for: sender, beep: true) else { return }
		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		pasteboard.writeObjects([node.pasteboardWriter])
		// A paste makes a new copy, even of a node that's still in the tree.
		PropertyListNode.clearPasteboardMapping()
	}

	/// The key (or "Item N") as plain text.
	@objc func copyKey(_ sender: Any?) {
		guard let node = node(for: sender, beep: true) else { return }
		Pasteboard.copy(node.displayKey)
	}

	/// The value as plain text, as the Value column shows it; arrays and dictionaries as XML.
	@objc func copyValue(_ sender: Any?) {
		guard let node = node(for: sender, beep: true) else { return }
		Pasteboard.copy(node.type.isContainer ? node.xmlString : node.type == .date ? node.sortValue : node.displayValue)
	}

	@objc func paste(_ sender: Any?) {
		guard validatePaste(sender), let pasted = PropertyListNode.node(from: .general) else {
			NSSound.beep()
			return
		}
		insert(pasted.parent == nil ? pasted : pasted.deepCopy(), forSender: sender)
	}

	@objc func delete(_ sender: Any?) {
		endEditing()
		guard let node = node(for: sender, beep: true) else { return }
		delete(node, notify: true, undoable: true)
	}

	/// The Value Type menu; the item's tag is the type.
	@objc func convertType(_ sender: NSMenuItem) {
		guard let type = PropertyListNode.Kind(rawValue: sender.tag), let node = node(for: sender, beep: true), canEditType(of: node) else { return }
		convert(node, to: type)
	}

	/// The Type column's pop-up.
	@objc func typeSelected(_ sender: NSPopUpButton) {
		guard let type = sender.selectedItem.flatMap({ PropertyListNode.Kind(rawValue: $0.tag) }),
		      let node = node(for: sender, beep: true) else { return }
		convert(node, to: type)
	}

	/// The Value column's YES / NO pop-up.
	@objc func booleanSelected(_ sender: NSPopUpButton) {
		guard let node = node(for: sender, beep: true) else { return }
		updateValue(sender.indexOfSelectedItem == 1, of: node, reloadItem: true)
	}

	@objc func dateChanged(_ sender: NSDatePicker) {
		guard let node = node(for: sender, beep: false) else { return }
		updateValue(sender.dateValue, of: node, reloadItem: false)
	}

	@objc func undo(_ sender: Any?) {
		editorUndoManager.undo()
	}

	@objc func redo(_ sender: Any?) {
		editorUndoManager.redo()
	}

	@objc private func outlineViewClicked(_ sender: Any?) {
		// A click on a date goes straight into its picker.
		let column = outlineView.clickedColumn, row = outlineView.clickedRow
		guard column >= 0, row >= 0, outlineView.tableColumns[column] === valueColumn,
		      let node = outlineView.item(atRow: row) as? PropertyListNode, node.appropriateType == .date,
		      let cell = outlineView.view(atColumn: column, row: row, makeIfNecessary: false) as? PropertyListCellView else { return }
		window?.makeFirstResponder(cell.datePicker)
	}

	@objc private func outlineViewDoubleClicked(_ sender: Any?) {
		let column = outlineView.clickedColumn, row = outlineView.clickedRow
		guard column >= 0, row >= 0, outlineView.tableColumns[column] !== typeColumn,
		      let node = outlineView.item(atRow: row) as? PropertyListNode else { return }
		if outlineView.tableColumns[column] === valueColumn && (node.appropriateType == .date || node.appropriateType.isContainer) {
			return
		}
		guard let textField = (outlineView.view(atColumn: column, row: row, makeIfNecessary: false) as? NSTableCellView)?.textField else { return }
		if textField.isEditable {
			outlineView.editColumn(column, row: row, with: NSApp.currentEvent, select: true)
		} else {
			// Read-only: select the text so it can be copied.
			window?.makeFirstResponder(textField)
			textField.selectText(nil)
		}
	}

	private func validatePaste(_ sender: Any?) -> Bool {
		let pasteboard = NSPasteboard.general
		guard isEditable, PropertyListNode.pasteboardHasNode(pasteboard) else { return false }
		let node = self.node(for: sender, beep: false)
		guard canInsert(at: node) else { return false }
		guard let pasted = PropertyListNode.node(from: pasteboard) else { return false }
		return canPaste(pasted, at: node)
	}
}

// MARK: - Menu validation

extension PropertyListEditor: NSMenuItemValidation {
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return false }
		let node = self.node(for: menuItem, beep: false)
		switch action {
		case #selector(undo(_:)):
			return editorUndoManager.canUndo
		case #selector(redo(_:)):
			return editorUndoManager.canRedo
		case #selector(add(_:)):
			return canInsert(at: node)
		case #selector(paste(_:)):
			return validatePaste(menuItem)
		case #selector(delete(_:)), #selector(cut(_:)):
			return node.map(canDelete) ?? false
		case #selector(convertType(_:)):
			guard let node = node else { return false }
			menuItem.state = node.type.rawValue == menuItem.tag ? .on : .off
			return canEditType(of: node)
		case #selector(copy(_:)), #selector(copyKey(_:)), #selector(copyValue(_:)):
			return node != nil
		default:
			return responds(to: action)
		}
	}
}

// MARK: - NSOutlineViewDataSource

extension PropertyListEditor: NSOutlineViewDataSource {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		guard let node = item as? PropertyListNode ?? rootNode else { return 0 }
		return node.children?.count ?? 0
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		let node = item as? PropertyListNode ?? rootNode
		return node!.children![index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		return (item as? PropertyListNode)?.type.isContainer ?? false
	}

	func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
		guard allowsColumnSorting else { return }
		// Ends any edit, so a text field doesn't commit into a row that's moved.
		window?.makeFirstResponder(outlineView)
		let selected = selectedNode
		sortRootNode(using: outlineView.sortDescriptors)
		outlineView.reloadItem(nil, reloadChildren: true)
		if let selected = selected {
			selectRow(for: selected)
			scrollRowToVisible(for: selected)
		}
	}

	func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
		return (item as? PropertyListNode)?.pasteboardWriter
	}

	func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
		guard isEditable, let parent = item as? PropertyListNode ?? rootNode, parent.type.isContainer,
		      let dragged = PropertyListNode.node(from: info.draggingPasteboard) else { return [] }
		let index = index < 0 ? parent.children?.count ?? 0 : index
		let wantsCopy = info.draggingSourceOperationMask == .copy
		return dragOperation(for: dragged, to: parent, at: index, wantsCopy: wantsCopy)
	}

	private func dragOperation(for dragged: PropertyListNode, to parent: PropertyListNode, at index: Int, wantsCopy: Bool) -> NSDragOperation {
		// From another editor or app: always a copy.
		guard dragged.parent != nil else {
			return canAddChild(in: parent) ? .copy : []
		}
		if !wantsCopy && delegate?.propertyListEditor(self, canMove: dragged, to: parent, at: index) == true {
			return .move
		}
		// Can't drop a container inside itself.
		var ancestor: PropertyListNode? = parent
		while let current = ancestor {
			if current === dragged {
				return []
			}
			ancestor = current.parent
		}
		let canRemove = wantsCopy || canDelete(dragged)
		guard canAddChild(in: parent) else { return [] }
		return canRemove && !wantsCopy ? .move : .copy
	}

	func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
		guard let parent = item as? PropertyListNode ?? rootNode, parent.type.isContainer,
		      let dragged = PropertyListNode.node(from: info.draggingPasteboard) else { return false }
		let index = index < 0 ? parent.children?.count ?? 0 : index
		if dragged.parent === parent && parent.children?.firstIndex(of: dragged) == index {
			return true
		}
		let wantsCopy = info.draggingSourceOperationMask == .copy
		if dragged.parent == nil || dragOperation(for: dragged, to: parent, at: index, wantsCopy: wantsCopy) == .copy {
			insert(dragged.deepCopy(), in: parent, at: index, notify: true, undoable: true)
		} else {
			move(dragged, into: parent, at: index, adjust: true)
		}
		return true
	}

	func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
		PropertyListNode.clearPasteboardMapping()
	}
}

// MARK: - NSOutlineViewDelegate

extension PropertyListEditor: NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		let rowView = PropertyListRowView()
		rowView.editor = self
		rowView.node = item as? PropertyListNode
		return rowView
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? PropertyListNode, let tableColumn = tableColumn else { return nil }
		let identifier: NSUserInterfaceItemIdentifier
		var string = ""
		var editable = false
		var dimmed = false

		if tableColumn === keyColumn {
			identifier = .plistKeyCell
			string = node.displayKey
			var transformed = false
			if let name = dataTransformer?.propertyListEditor(self, displayNameFor: node), name != string {
				string = name
				transformed = true
			}
			editable = !transformed && (node.parent == nil || node.parent?.type == .dictionary) && canEditKey(of: node)
		} else if tableColumn === typeColumn {
			identifier = .plistTypeCell
			node.cachedDisplayValue = node.type.isContainer ? nil : dataTransformer?.propertyListEditor(self, displayValueFor: node)
			editable = canEditType(of: node)
		} else {
			let type = node.appropriateType
			identifier = type == .boolean ? .plistBoolCell : type == .date ? .plistDateCell : .plistValueCell
			string = node.displayValue
			editable = !type.isContainer && canEditValue(of: node)
			dimmed = type.isContainer
		}

		let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? PropertyListCellView
			?? PropertyListCellView(identifier: identifier, editor: self)
		switch identifier {
		case .plistTypeCell:
			cell.setType(node.appropriateType)
		case .plistBoolCell:
			cell.setBoolean((node.cachedDisplayValue ?? node.value) as? Bool ?? false)
		case .plistDateCell:
			cell.setDate((node.cachedDisplayValue ?? node.value) as? Date ?? Date())
		default:
			cell.setString(string, toolTip: tableColumn === keyColumn || tableColumn === valueColumn)
		}
		cell.setEditable(editable, dimmed: dimmed)
		cell.textField?.delegate = self
		return cell
	}

	func outlineViewItemDidExpand(_ notification: Notification) {
		updateEditButtons(for: notification)
	}

	func outlineViewItemDidCollapse(_ notification: Notification) {
		updateEditButtons(for: notification)
	}

	private func updateEditButtons(for notification: Notification) {
		guard let item = notification.userInfo?["NSObject"] else { return }
		(outlineView.rowView(atRow: outlineView.row(forItem: item), makeIfNecessary: false) as? PropertyListRowView)?.updateEditButtons()
	}

	func outlineViewColumnDidResize(_ notification: Notification) {
		outlineView.sizeLastColumnToFit()
	}
}

// MARK: - Editing text

extension PropertyListEditor: NSTextFieldDelegate {
	func controlTextDidEndEditing(_ notification: Notification) {
		guard let textField = notification.object as? NSTextField else { return }
		let row = outlineView.row(for: textField), column = outlineView.column(for: textField)
		guard row >= 0, column >= 0, let node = outlineView.item(atRow: row) as? PropertyListNode else { return }
		let cell = textField.superview as? PropertyListCellView

		if outlineView.tableColumns[column] === keyColumn {
			let key = textField.stringValue
			guard key != node.key else { return }
			if keyExists(key, in: node.parent, excluding: node) {
				textField.stringValue = node.key ?? ""
				cell?.flashError()
				let alert = NSAlert()
				alert.alertStyle = .warning
				alert.messageText = String(format: L("The key “%@” already exists in containing item."), key)
				alert.addButton(withTitle: L("OK"))
				alert.runModal()
			} else {
				updateKey(key, of: node)
			}
		} else if outlineView.tableColumns[column] === valueColumn {
			if let value = PropertyListNode.value(from: textField.stringValue, type: node.appropriateType) {
				updateValue(value, of: node, reloadItem: true)
			} else {
				textField.stringValue = node.displayValue
				cell?.flashError()
			}
		}
	}
}
