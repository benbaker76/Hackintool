//
//  NVRAMViewController.swift
//  Hackintool
//
//  NVRAM section: variables in a table, the selected value in an editor below.
//  Changes are written only when Save is pressed.
//

import Cocoa

final class NVRAMViewController: NSViewController, SectionContent, NSTextViewDelegate {
	private let table = DataTableViewController<NVRAMVariable>(columns: [
		DataColumn("Name", "Name", width: 320) { $0.name },
		DataColumn("Type", "Type", width: 70) { $0.typeName },
		DataColumn("Value", "Value", width: 400, monospaced: true) { $0.summary },
	])
	private let editor = ScrollingTextView(editable: true, monospaced: true)
	private lazy var saveButton = ControlBar.button("Save", target: self, action: #selector(save(_:)))
	private lazy var revertButton = ControlBar.button("Revert", target: self, action: #selector(revert(_:)))
	private lazy var deleteButton = ControlBar.iconButton(.remove, toolTip: "Delete", target: self, action: #selector(deleteVariable(_:)))

	private var selected: NVRAMVariable?

	override func loadView() {
		addChild(table)
		table.tableView.allowsMultipleSelection = false
		table.onSelectionChange = { [weak self] rows in self?.select(rows.first) }
		editor.textView.delegate = self

		let editorBar = ControlBar.make([
			ControlBar.iconButton(.add, toolTip: "Add", target: self, action: #selector(addVariable(_:))),
			deleteButton,
		], trailing: [revertButton, saveButton])

		let split = NSSplitView()
		split.isVertical = false
		split.dividerStyle = .thin
		split.addArrangedSubview(table.view)
		split.addArrangedSubview(ControlBar.stack(header: nil, content: editor.scrollView, footer: editorBar))
		split.arrangedSubviews[1].heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
		let tableHeight = split.arrangedSubviews[0].heightAnchor.constraint(equalTo: split.heightAnchor, multiplier: 0.6)
		tableHeight.priority = .defaultLow
		tableHeight.isActive = true
		view = split
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		refresh()
	}

	private func select(_ variable: NVRAMVariable?) {
		selected = variable
		editor.string = variable?.editableText ?? ""
		editor.textView.isEditable = variable != nil
		updateButtons()
	}

	private var hasChanges: Bool {
		guard let selected = selected else { return false }
		return editor.string != selected.editableText
	}

	private func updateButtons() {
		saveButton.isEnabled = hasChanges
		revertButton.isEnabled = hasChanges
		deleteButton.isEnabled = selected != nil
	}

	func textDidChange(_ notification: Notification) {
		updateButtons()
	}

	// MARK: SectionContent

	var canRefresh: Bool { return true }

	func refresh() {
		let selectedName = selected?.name
		table.setRows(NVRAM.variables())
		if let name = selectedName, let index = table.visibleRows.firstIndex(where: { $0.name == name }) {
			table.tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
		} else {
			select(nil)
		}
	}

	var searchPlaceholder: String? { return table.searchPlaceholder }
	func search(_ text: String) { table.search(text) }

	// MARK: Actions

	@objc private func save(_ sender: Any?) {
		guard let variable = selected else { return }
		if NVRAM.save(editor.string, to: variable) {
			refresh()
		} else {
			Alerts.error("Couldn't save the NVRAM variable.", "Check the value is valid; binary values must be hex bytes.")
		}
	}

	@objc private func revert(_ sender: Any?) {
		select(selected)
	}

	@objc private func deleteVariable(_ sender: Any?) {
		guard let variable = selected else { return }
		Alerts.confirm(L("Delete “%@”?", variable.name), "This removes the variable from NVRAM.", confirmTitle: "Delete") { confirmed in
			guard confirmed else { return }
			NVRAM.delete(variable.name)
			self.refresh()
		}
	}

	@objc private func addVariable(_ sender: Any?) {
		let nameField = NSComboBox()
		nameField.addItems(withObjectValues: ["boot-args", "csr-active-config", "prev-lang:kbd", "SystemAudioVolume"])
		nameField.placeholderString = L("Name")
		let typePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
		typePopUp.addItems(withTitles: [L("String"), L("Data (hex)")])
		let valueField = Form.textField(monospaced: true, placeholder: "Value")
		let form = Form.grid([("Name", nameField), ("Type", typePopUp), ("Value", valueField)])
		form.frame = NSRect(x: 0, y: 0, width: 360, height: 90)

		let alert = NSAlert()
		alert.messageText = L("Add NVRAM Variable")
		alert.accessoryView = form
		alert.addButton(withTitle: L("Add"))
		alert.addButton(withTitle: L("Cancel"))
		alert.window.initialFirstResponder = nameField
		guard let window = view.window else { return }
		alert.beginSheetModal(for: window) { response in
			let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
			guard response == .alertFirstButtonReturn, !name.isEmpty else { return }
			let succeeded: Bool
			if typePopUp.indexOfSelectedItem == 0 {
				succeeded = NVRAM.set(name, string: valueField.stringValue)
			} else if let data = Data(hexString: valueField.stringValue) {
				succeeded = NVRAM.set(name, data: data)
			} else {
				succeeded = false
			}
			if !succeeded {
				Alerts.error("Couldn't save the NVRAM variable.", "Check the value is valid; binary values must be hex bytes.")
			}
			self.refresh()
		}
	}
}
