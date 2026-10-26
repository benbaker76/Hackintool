//
//  FlagChecklist.swift
//  Hackintool
//
//  A table of named bit flags with a checkbox per bit, for framebuffer and connector flags.
//

import Cocoa

final class FlagChecklist: NSViewController {
	struct Row {
		let bit: Int
		let name: String
		let isOn: Bool
	}

	/// Called with the new flags value when a box is ticked or cleared.
	var onChange: ((UInt32) -> Void)?

	private let names: [String]
	private var value: UInt32 = 0
	private lazy var table = DataTableViewController<Row>(columns: [
		DataColumn("On", "", width: 24) { $0.isOn ? "1" : "0" }
			.with(customView: { [unowned self] row in self.checkbox(for: row) }),
		DataColumn("Name", "Name", width: 260) { $0.name },
		DataColumn("Bit", "Value", width: 90, monospaced: true, sortKey: { .number(Double($0.bit)) }) { String(format: "0x%X", 1 << $0.bit) },
	])

	init(names: [String]) {
		self.names = names
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	override func loadView() {
		addChild(table)
		table.tableView.usesAlternatingRowBackgroundColors = false
		view = table.view
	}

	/// Shows the bits of `value`; nil disables the list (the record has no flags field).
	func show(_ value: UInt32?) {
		self.value = value ?? 0
		table.setRows(value == nil ? [] : names.enumerated().map { Row(bit: $0.offset, name: $0.element, isOn: (value! >> UInt32($0.offset)) & 1 != 0) })
	}

	private func checkbox(for row: Row) -> NSView {
		let checkbox = BitCheckbox(bit: row.bit, target: self, action: #selector(toggled(_:)))
		checkbox.state = row.isOn ? .on : .off
		checkbox.toolTip = toolTip(row.name)
		return checkbox
	}

	@objc private func toggled(_ sender: BitCheckbox) {
		let mask = UInt32(1) << UInt32(sender.bit)
		value = sender.state == .on ? value | mask : value & ~mask
		onChange?(value)
	}
}

final class BitCheckbox: NSButton {
	let bit: Int

	init(bit: Int, target: AnyObject, action: Selector) {
		self.bit = bit
		super.init(frame: .zero)
		setButtonType(.switch)
		title = ""
		self.target = target
		self.action = action
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}
}
