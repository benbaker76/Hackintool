//
//  PropertyListEditorViews.swift
//  Hackintool
//
//  The outline view, rows and cells of the property list editor.
//
//  Swift port of LNPropertyListEditor by Leo Natan (https://github.com/LeoNatan/LNPropertyListEditor).
//  Copyright © 2018-2021 Leo Natan. Released under the MIT License.
//

import Cocoa

extension NSUserInterfaceItemIdentifier {
	static let plistKeyColumn = NSUserInterfaceItemIdentifier("Key")
	static let plistTypeColumn = NSUserInterfaceItemIdentifier("Type")
	static let plistValueColumn = NSUserInterfaceItemIdentifier("Value")
	static let plistKeyCell = NSUserInterfaceItemIdentifier("KeyCell")
	static let plistTypeCell = NSUserInterfaceItemIdentifier("TypeCell")
	static let plistValueCell = NSUserInterfaceItemIdentifier("ValueCell")
	static let plistBoolCell = NSUserInterfaceItemIdentifier("BoolCell")
	static let plistDateCell = NSUserInterfaceItemIdentifier("DateCell")
}

final class PropertyListOutlineView: NSOutlineView {
	override func layout() {
		super.layout()
		if let last = tableColumns.last, last.resizingMask.contains(.autoresizingMask) {
			sizeLastColumnToFit()
		}
	}
}

/// Ignores right clicks unless it's being edited, so the row's context menu opens instead.
final class PropertyListCellTextField: NSTextField {
	override func hitTest(_ point: NSPoint) -> NSView? {
		let type = NSApp.currentEvent?.type
		if (currentEditor() == nil || window?.firstResponder != currentEditor()) && (type == .rightMouseDown || type == .rightMouseUp) {
			return nil
		}
		return super.hitTest(point)
	}
}

/// A borderless pop-up whose title is coloured like the text fields beside it.
final class PropertyListPopUpButtonCell: NSPopUpButtonCell {
	override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
		let highlighted = backgroundStyle == .emphasized
		let color: NSColor
		if isEnabled {
			color = highlighted ? .alternateSelectedControlTextColor : .labelColor
		} else {
			color = highlighted ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.6) : .secondaryLabelColor
		}
		let text = NSMutableAttributedString(attributedString: attributedTitle)
		text.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: text.length))
		text.draw(in: frame)
		return frame
	}
}

final class PropertyListCellView: NSTableCellView {
	private(set) var typeButton: NSPopUpButton?
	private(set) var datePicker: NSDatePicker?
	private var plusButton: NSButton?
	private var minusButton: NSButton?
	private var buttonsConstraint: NSLayoutConstraint?
	private(set) var showsControlButtons = false

	static let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

	/// Builds the cell for one of the plist cell identifiers.
	init(identifier: NSUserInterfaceItemIdentifier, editor: PropertyListEditor) {
		super.init(frame: .zero)
		self.identifier = identifier
		switch identifier {
		case .plistKeyCell:
			let field = makeTextField()
			let minus = makeEditButton(.remove, toolTip: "Delete", target: editor, action: #selector(PropertyListEditor.delete(_:)))
			let plus = makeEditButton(.add, toolTip: "Add Item", target: editor, action: #selector(PropertyListEditor.add(_:)))
			let trailing = field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2)
			trailing.priority = NSLayoutConstraint.Priority(999)
			NSLayoutConstraint.activate([
				field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
				field.centerYAnchor.constraint(equalTo: centerYAnchor),
				trailing,
				minus.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
				minus.centerYAnchor.constraint(equalTo: centerYAnchor),
				minus.leadingAnchor.constraint(equalTo: plus.trailingAnchor, constant: 2),
				plus.centerYAnchor.constraint(equalTo: centerYAnchor),
			])
			buttonsConstraint = plus.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 4)
			plusButton = plus
			minusButton = minus
		case .plistValueCell:
			let field = makeTextField()
			NSLayoutConstraint.activate([
				field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
				field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
				field.centerYAnchor.constraint(equalTo: centerYAnchor),
			])
		case .plistTypeCell:
			let menu = NSMenu()
			for kind in PropertyListNode.Kind.menuOrder {
				guard let kind = kind else {
					menu.addItem(.separator())
					continue
				}
				let item = NSMenuItem(title: L(kind.name), action: nil, keyEquivalent: "")
				item.tag = kind.rawValue
				menu.addItem(item)
			}
			typeButton = makePopUp(menu: menu, target: editor, action: #selector(PropertyListEditor.typeSelected(_:)))
		case .plistBoolCell:
			let menu = NSMenu()
			menu.addItem(withTitle: "NO", action: nil, keyEquivalent: "")
			menu.addItem(withTitle: "YES", action: nil, keyEquivalent: "")
			typeButton = makePopUp(menu: menu, target: editor, action: #selector(PropertyListEditor.booleanSelected(_:)))
		case .plistDateCell:
			let picker = NSDatePicker()
			picker.datePickerStyle = .textField
			picker.datePickerElements = [.yearMonthDay, .hourMinuteSecond, .timeZone]
			picker.isBordered = false
			picker.isBezeled = false
			picker.drawsBackground = false
			picker.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
			picker.target = editor
			picker.action = #selector(PropertyListEditor.dateChanged(_:))
			picker.translatesAutoresizingMaskIntoConstraints = false
			addSubview(picker)
			NSLayoutConstraint.activate([
				picker.leadingAnchor.constraint(equalTo: leadingAnchor),
				picker.centerYAnchor.constraint(equalTo: centerYAnchor),
			])
			datePicker = picker
		default:
			break
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	private func makeTextField() -> NSTextField {
		let field = PropertyListCellTextField()
		field.isBordered = false
		field.drawsBackground = false
		field.font = PropertyListCellView.font
		field.lineBreakMode = .byTruncatingTail
		field.usesSingleLineMode = true
		field.cell?.isScrollable = false
		field.cell?.wraps = false
		field.cell?.sendsActionOnEndEditing = true
		field.translatesAutoresizingMaskIntoConstraints = false
		field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		addSubview(field)
		textField = field
		return field
	}

	private func makeEditButton(_ symbol: Symbol, toolTip: String, target: AnyObject, action: Selector) -> NSButton {
		let button = NSButton(image: symbol.image(description: L(toolTip)), target: target, action: action)
		button.isBordered = false
		button.imageScaling = .scaleProportionallyDown
		button.toolTip = L(toolTip)
		button.isHidden = true
		button.translatesAutoresizingMaskIntoConstraints = false
		addSubview(button)
		NSLayoutConstraint.activate([
			button.widthAnchor.constraint(equalToConstant: 13),
			button.heightAnchor.constraint(equalToConstant: 13),
		])
		return button
	}

	private func makePopUp(menu: NSMenu, target: AnyObject, action: Selector) -> NSPopUpButton {
		let button = NSPopUpButton(frame: .zero, pullsDown: false)
		button.cell = PropertyListPopUpButtonCell(textCell: "", pullsDown: false)
		button.menu = menu
		button.isBordered = false
		button.controlSize = .small
		button.font = PropertyListCellView.font
		(button.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
		button.target = target
		button.action = action
		button.translatesAutoresizingMaskIntoConstraints = false
		addSubview(button)
		NSLayoutConstraint.activate([
			button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -1),
			button.trailingAnchor.constraint(equalTo: trailingAnchor),
			button.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		return button
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		plusButton?.isHidden = true
		minusButton?.isHidden = true
		buttonsConstraint?.isActive = false
		toolTip = nil
	}

	func setString(_ string: String, toolTip: Bool) {
		if let typeButton = typeButton {
			typeButton.selectItem(withTitle: string)
		} else {
			textField?.stringValue = string
		}
		self.toolTip = toolTip && !string.isEmpty ? string : nil
	}

	func setType(_ kind: PropertyListNode.Kind) {
		typeButton?.selectItem(withTag: kind.rawValue)
	}

	func setBoolean(_ value: Bool) {
		typeButton?.selectItem(at: value ? 1 : 0)
	}

	func setDate(_ date: Date) {
		datePicker?.dateValue = date
	}

	func setEditable(_ editable: Bool, dimmed: Bool = false) {
		textField?.isEditable = editable
		// Read-only text can still be selected and copied.
		textField?.isSelectable = true
		textField?.textColor = dimmed ? .secondaryLabelColor : .labelColor
		typeButton?.isEnabled = editable
		// A pop-up that can't be changed shouldn't look like one.
		(typeButton?.cell as? NSPopUpButtonCell)?.arrowPosition = editable ? .arrowAtBottom : .noArrow
		datePicker?.isEnabled = editable
		datePicker?.textColor = .labelColor
	}

	func setShowsControlButtons(_ shows: Bool, addEnabled: Bool, deleteEnabled: Bool) {
		showsControlButtons = shows && (addEnabled || deleteEnabled)
		plusButton?.isHidden = !showsControlButtons
		minusButton?.isHidden = !showsControlButtons
		buttonsConstraint?.isActive = showsControlButtons
		plusButton?.isEnabled = addEnabled
		minusButton?.isEnabled = deleteEnabled
	}

	override var backgroundStyle: NSView.BackgroundStyle {
		didSet { datePicker?.cell?.backgroundStyle = backgroundStyle }
	}

	/// Flashes the cell red when an edit is rejected.
	func flashError() {
		wantsLayer = true
		let flash = CABasicAnimation(keyPath: "backgroundColor")
		flash.fromValue = NSColor.clear.cgColor
		flash.toValue = NSColor.systemRed.cgColor
		flash.duration = 0.25
		flash.autoreverses = true
		flash.timingFunction = CAMediaTimingFunction(name: .easeOut)
		layer?.add(flash, forKey: "backgroundColor")
	}
}

/// Shows the + and − buttons while the row is hovered or selected.
final class PropertyListRowView: NSTableRowView {
	weak var editor: PropertyListEditor?
	var node: PropertyListNode?
	private var mouseInside = false
	private var trackingArea: NSTrackingArea?

	func updateEditButtons() {
		guard let editor = editor, let node = node, numberOfColumns > 0,
		      let cell = view(atColumn: 0) as? PropertyListCellView else { return }
		cell.setShowsControlButtons(isSelected || mouseInside,
		                            addEnabled: editor.canInsert(at: node),
		                            deleteEnabled: editor.canDelete(node))
	}

	override var isSelected: Bool {
		didSet { updateEditButtons() }
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if trackingArea == nil {
			trackingArea = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil)
		}
		if let trackingArea = trackingArea, !trackingAreas.contains(trackingArea) {
			addTrackingArea(trackingArea)
		}
	}

	override func mouseEntered(with event: NSEvent) {
		mouseInside = true
		updateEditButtons()
	}

	override func mouseExited(with event: NSEvent) {
		mouseInside = false
		updateEditButtons()
	}
}
