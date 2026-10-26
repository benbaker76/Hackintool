//
//  FramebufferViewController.swift
//  Hackintool
//
//  Patch section: Intel framebuffer patching. Choose a platform ID, edit its framebuffer
//  record and connectors, then generate WhateverGreen properties or KextsToPatch.
//

import Cocoa

final class FramebufferViewController: TabbedViewController, NSMenuItemValidation {
	let model = FramebufferModel()

	init() {
		let model = self.model
		super.init(identifier: "Framebuffer", pages: [
			Page(title: L("Info"), viewController: FramebufferInfoViewController(model: model)),
			Page(title: L("Framebuffer"), viewController: FramebufferEditorViewController(model: model)),
			Page(title: L("Patch"), viewController: FramebufferPatchViewController(model: model)),
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		model.load()
	}

	// MARK: Menu commands (File and Framebuffer menus)

	/// File ▸ Open…: load the IGPU properties from a config.plist into the editor.
	@objc func openDocument(_ sender: Any?) {
		FilePanels.open(allowedExtensions: ["plist"]) { url in
			self.openConfig(at: url)
		}
	}

	func openConfig(at url: URL) {
		guard let config = ConfigPlist(contentsOf: url, format: BootloaderConfigFormat.current) else {
			Alerts.error("Couldn't read the config.plist.", url.path)
			return
		}
		let gpuPath = model.context?.gpuDevice?.devicePath ?? PatchContext.fakeIGPU.devicePath
		guard let properties = config.deviceProperties[gpuPath] as? [String: Any] else {
			Alerts.error("No IGPU properties found.", L("“%@” has no DeviceProperties for %@.", url.lastPathComponent, gpuPath))
			return
		}
		NSDocumentController.shared.noteNewRecentDocumentURL(url)
		model.apply(properties: properties)
	}

	/// File ▸ Export ▸ Bootloader config.plist: merge the generated properties into a config.plist.
	@objc func exportBootloaderConfig(_ sender: Any?) {
		FramebufferPatchViewController.saveToConfig(model: model)
	}

	@objc func exportFramebufferText(_ sender: Any?) {
		guard let table = model.table else { return }
		FilePanels.save(suggestedName: "\(model.generation.name).txt", allowedExtensions: ["txt"]) { url in
			try? table.report().write(to: url, atomically: true, encoding: .utf8)
		}
	}

	@objc func exportFramebufferBinary(_ sender: Any?) {
		guard let table = model.table else { return }
		FilePanels.save(suggestedName: "\(model.generation.name).bin", allowedExtensions: ["bin"]) { url in
			try? table.binary.write(to: url)
		}
	}

	@objc func selectFramebufferSource(_ sender: NSMenuItem) {
		guard let source = FramebufferTable.Source(rawValue: sender.tag) else { return }
		model.setSource(source)
	}

	@objc func toggleApplyCurrentPatches(_ sender: NSMenuItem) {
		Settings.applyCurrentPatches.toggle()
		model.setSource(model.source)
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(selectFramebufferSource(_:)):
			menuItem.state = menuItem.tag == model.source.rawValue ? .on : .off
		case #selector(toggleApplyCurrentPatches(_:)):
			menuItem.state = Settings.applyCurrentPatches ? .on : .off
		case #selector(exportFramebufferText(_:)), #selector(exportFramebufferBinary(_:)), #selector(exportBootloaderConfig(_:)):
			return model.table != nil
		default:
			break
		}
		return true
	}

	/// Patch ▸ Import KextsToPatch: apply a find/replace pair to the table.
	@objc func importKextsToPatch(_ sender: Any?) {
		let find = Form.textField(monospaced: true, placeholder: "Find (hex)")
		let replace = Form.textField(monospaced: true, placeholder: "Replace (hex)")
		let form = Form.grid([("Find", find), ("Replace", replace)])
		form.frame = NSRect(x: 0, y: 0, width: 420, height: 60)
		let alert = NSAlert()
		alert.messageText = L("Import KextsToPatch")
		alert.accessoryView = form
		alert.addButton(withTitle: L("Import"))
		alert.addButton(withTitle: L("Cancel"))
		guard let window = view.window else { return }
		alert.beginSheetModal(for: window) { response in
			guard response == .alertFirstButtonReturn,
			      let findData = Data(hexString: find.stringValue), let replaceData = Data(hexString: replace.stringValue),
			      !findData.isEmpty, findData.count == replaceData.count else { return }
			let replaced = self.model.findAndReplace(findData, with: replaceData)
			Alerts.show("Importing KextsToPatch", replaced > 0 ? "Patch Success!" : "Patch Fail!")
		}
	}

	/// Patch ▸ System Configs ▸ …: load a known-good board configuration.
	@objc func loadSystemConfig(_ sender: NSMenuItem) {
		guard let url = sender.representedObject as? URL, let config = ConfigPlist(contentsOf: url, format: .clover) else { return }
		let devices = config.deviceProperties.allValues.compactMap { $0 as? [String: Any] }
		// The IGPU entry is the one with a platform ID; presets may also carry audio properties.
		guard let properties = devices.first(where: { $0["AAPL,ig-platform-id"] != nil || $0["AAPL,snb-platform-id"] != nil }) ?? devices.first else { return }
		model.apply(properties: properties)
	}

	/// Patch ▸ AzulPatcher4600: the well-known Haswell HD 4600 desktop patch set.
	@objc func applyAzulPatcher4600(_ sender: Any?) {
		Settings.injectDeviceID = true
		Settings.useAllDataMethod = true
		Settings.disableeGPU = true
		model.setGeneration(.haswell)
		model.select(platformID: 0x0A26_0006)
		model.injectedDeviceIndex = model.deviceIDs.firstIndex(of: 0x0412) ?? model.injectedDeviceIndex
		let patches: [([UInt8], [UInt8])] = [
			// Disable port 0204.
			([0x02, 0x04, 0x09, 0x00, 0x00, 0x04, 0x00, 0x00, 0x87, 0x00, 0x00, 0x00], [0xFF, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00]),
			// 9 MB cursor bytes, 2 ports only.
			([0x06, 0x00, 0x26, 0x0A, 0x01, 0x03, 0x03, 0x03, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x30, 0x01, 0x00, 0x00, 0x60, 0x00],
			 [0x06, 0x00, 0x26, 0x0A, 0x01, 0x03, 0x02, 0x02, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x30, 0x01, 0x00, 0x00, 0x90, 0x00]),
			// HDMI audio.
			([0x01, 0x05, 0x09, 0x00, 0x00, 0x04, 0x00, 0x00, 0x87, 0x00, 0x00, 0x00], [0x01, 0x05, 0x12, 0x00, 0x00, 0x08, 0x00, 0x00, 0x87, 0x00, 0x00, 0x00]),
		]
		for (find, replace) in patches {
			model.findAndReplace(Data(find), with: Data(replace))
		}
	}
}

// MARK: - Info

/// Patch ▸ Info: the selected framebuffer, this Mac's graphics, and memory totals.
final class FramebufferInfoViewController: PropertyListViewController {
	private let model: FramebufferModel

	init(model: FramebufferModel) {
		self.model = model
		super.init(showsGroupHeaders: true)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		model.observe { [weak self] in self?.update() }
		update()
	}

	private func update() {
		guard let framebuffer = model.modified, let platformID = model.platformID else {
			setGroups([])
			return
		}
		let generation = model.generation
		var selected = [
			PropertyItem("Intel Generation", generation.displayName),
			PropertyItem("Platform ID", platformID.hex8),
		]
		if let deviceID = FramebufferTable.gpuDeviceID(for: platformID, generation: generation) {
			selected.append(PropertyItem("GPU Device ID", deviceID.hex8))
			selected.append(PropertyItem("GPU Name", FramebufferTable.gpuName(for: platformID, generation: generation)))
		}
		selected += [
			PropertyItem("Mobile", L(framebuffer.isMobile ? "Yes" : "No")),
			PropertyItem("Intel Platform ID(s)", model.table?.platformIDs.map { $0.hex8 }.joined(separator: " ")),
			PropertyItem("GPU Device ID(s)", model.deviceIDs.map { String(format: "0x%04X", $0) }.joined(separator: " ")),
			PropertyItem("Model(s)", FramebufferTable.modelNames(for: platformID)),
		]
		if model.isHeadless {
			selected.append(PropertyItem("", L("Headless (no display outputs)")))
		}

		let machine = Machine.shared
		let gpu = machine.integratedGPU
		let current = [
			PropertyItem("Model", machine.modelIdentifier),
			PropertyItem("Intel Generation", machine.intelGeneration?.displayName),
			PropertyItem("Platform ID", machine.platformID?.hex8),
			PropertyItem("GPU Device ID", gpu.map { ($0.deviceID << 16 | $0.vendorID).hex8 }),
			PropertyItem("GPU Name", gpu?.model),
		]

		let memory = { (value: UInt32?) in value.map { ByteFormatting.memory($0) } }
		let vram = [
			PropertyItem("Stolen", memory(framebuffer.stolenMemory)),
			PropertyItem("FBMem", memory(framebuffer.framebufferMemory)),
			PropertyItem("VRAM", memory(framebuffer.unifiedMemory)),
			PropertyItem("Max Stolen", memory(framebuffer.maxStolenMemory)),
			PropertyItem("Total Stolen", memory(framebuffer.totalStolenMemory)),
			PropertyItem("Total Cursor", memory(framebuffer.totalCursorMemory)),
			PropertyItem("Max Overall", memory(framebuffer.maxOverallMemory)),
		]

		setGroups([
			PropertyGroup("Selected Framebuffer", selected),
			PropertyGroup("Current Framebuffer", current),
			PropertyGroup("VRAM", vram),
		])
	}
}

// MARK: - Editor

/// Patch ▸ Framebuffer: pick a platform and edit its fields, flags and connectors.
final class FramebufferEditorViewController: NSViewController, SectionContent {
	private let model: FramebufferModel

	private struct FieldRow {
		let field: FramebufferField
		let value: String
		let isModified: Bool
	}

	private struct ConnectorRow {
		let index: Int
		let connector: Connector
		let isModified: Bool
	}

	private lazy var generationPopUp = ControlBar.popUp(IntelGeneration.allCases.map { $0.displayName }, target: self, action: #selector(generationChanged(_:)))
	private lazy var platformPopUp = ControlBar.popUp([], target: self, action: #selector(platformChanged(_:)))
	private lazy var sourcePopUp = ControlBar.popUp(
		[L("Installed Kext"), "macOS 10.13.6", "macOS 10.14", L("IOReg Dump (Native)"), L("IOReg Dump (Patched)")],
		target: self, action: #selector(sourceChanged(_:)))

	private lazy var fields = DataTableViewController<FieldRow>(columns: [
		DataColumn("Name", "Name", width: 190) { L($0.field.name) },
		DataColumn("Value", "Value", width: 170, monospaced: true, onEdit: { [weak self] row, text in
			self?.model.modify { framebuffer in
				if !row.field.parse(text, into: &framebuffer) { NSSound.beep() }
			}
		}) { $0.value },
	])
	private let framebufferFlags = FlagChecklist(names: framebufferFlagNames)

	private lazy var connectors = DataTableViewController<ConnectorRow>(columns: [
		DataColumn("Index", "Index", width: 50, sortKey: { .number(Double($0.index)) }, onEdit: { [weak self] row, text in
			self?.editConnector(row) { $0.index = Int32(text) ?? $0.index }
		}) { String($0.connector.index) },
		DataColumn("BusID", "Bus ID", width: 60, monospaced: true, onEdit: { [weak self] row, text in
			self?.editConnector(row) { $0.busID = text.hexOrDecimalValue.map { UInt32(truncatingIfNeeded: $0) } ?? $0.busID }
		}) { String(format: "0x%02X", $0.connector.busID) },
		DataColumn("Pipe", "Pipe", width: 50, onEdit: { [weak self] row, text in
			self?.editConnector(row) { $0.pipe = UInt32(text) ?? $0.pipe }
		}) { String($0.connector.pipe) },
		DataColumn("Type", "Type", width: 120) { $0.connector.typeName }
			.with(customView: { [unowned self] row in self.typePopUp(for: row) }),
		DataColumn("Flags", "Flags", width: 100, monospaced: true, onEdit: { [weak self] row, text in
			self?.editConnector(row) { $0.flags = UInt32(text.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive), radix: 16) ?? $0.flags }
		}) { String(format: "0x%08X", $0.connector.flags) },
	])
	private let connectorFlags = FlagChecklist(names: connectorFlagNames)
	private var selectedConnector = 0

	init(model: FramebufferModel) {
		self.model = model
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	override func loadView() {
		[fields, framebufferFlags, connectors, connectorFlags].forEach(addChild)
		fields.rowColor = { $0.isModified ? .systemOrange : nil }
		connectors.rowColor = { [unowned self] row in
			if row.isModified {
				return .systemOrange
			}
			// Connectors with an Intel-driven display attached: green for the built-in panel, red otherwise.
			guard let display = self.attachedDisplay(row) else { return nil }
			return display.isInternal ? .systemGreen : .systemRed
		}
		connectors.tableView.allowsMultipleSelection = false
		connectors.onSelectionChange = { [weak self] rows in
			guard let self = self, let row = rows.first else { return }
			self.selectedConnector = row.index
			self.connectorFlags.show(row.connector.flags)
		}
		framebufferFlags.onChange = { [weak self] value in self?.model.modify { $0.flags = value } }
		connectorFlags.onChange = { [weak self] value in
			guard let self = self else { return }
			let index = self.selectedConnector
			self.model.modify { framebuffer in
				var connector = framebuffer.connector(at: index)
				connector.flags = value
				framebuffer.setConnector(connector, at: index)
			}
		}
		platformPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

		let header = ControlBar.make([
			ControlBar.label("Intel Generation"), generationPopUp,
			ControlBar.label("Platform ID"), platformPopUp,
		], trailing: [
			sourcePopUp,
			ControlBar.button("Reset", symbol: .refresh, target: self, action: #selector(reset(_:))),
		])

		func pane(_ title: String, _ content: NSView, trailing: [NSView] = []) -> NSView {
			return ControlBar.stack(header: ControlBar.make([ControlBar.heading(title)], trailing: trailing), content: content)
		}
		let left = NSSplitView()
		left.isVertical = false
		left.dividerStyle = .thin
		left.addArrangedSubview(pane("Framebuffer", fields.view))
		left.addArrangedSubview(pane("Flags", framebufferFlags.view))

		let right = NSSplitView()
		right.isVertical = false
		right.dividerStyle = .thin
		right.addArrangedSubview(pane("Connectors", connectors.view, trailing: [
			ControlBar.iconButton(.export, toolTip: "Move Up", target: self, action: #selector(moveConnectorUp(_:))),
			ControlBar.iconButton(.import, toolTip: "Move Down", target: self, action: #selector(moveConnectorDown(_:))),
		]))
		right.addArrangedSubview(pane("Connector Flags", connectorFlags.view))
		for split in [left, right] {
			let top = split.arrangedSubviews[0].heightAnchor.constraint(equalTo: split.heightAnchor, multiplier: 0.5)
			top.priority = .defaultLow
			top.isActive = true
		}

		let columns = NSSplitView()
		columns.isVertical = true
		columns.dividerStyle = .thin
		columns.addArrangedSubview(left)
		columns.addArrangedSubview(right)
		let leftWidth = left.widthAnchor.constraint(equalTo: columns.widthAnchor, multiplier: 0.45)
		leftWidth.priority = .defaultLow
		leftWidth.isActive = true

		view = ControlBar.stack(header: header, content: columns)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		model.observe { [weak self] in self?.update() }
		update()
	}

	private func update() {
		generationPopUp.selectItem(at: model.generation.rawValue)
		sourcePopUp.selectItem(at: model.source.rawValue)
		platformPopUp.removeAllItems()
		if let table = model.table {
			for id in table.platformIDs {
				let name = FramebufferTable.gpuName(for: id, generation: model.generation)
				platformPopUp.addItem(withTitle: id.hex8 + (name.map { " — \($0)" } ?? ""))
			}
			platformPopUp.selectItem(at: model.index)
		}
		guard let original = model.original, let modified = model.modified else {
			fields.setRows([])
			connectors.setRows([])
			framebufferFlags.show(nil)
			connectorFlags.show(nil)
			return
		}
		fields.setRows(FramebufferField.allCases.compactMap { field in
			guard let value = field.display(modified) else { return nil }
			return FieldRow(field: field, value: value, isModified: field.display(original) != value)
		})
		framebufferFlags.show(modified.flags)
		connectors.setRows((0..<modified.layout.connectorCount).map {
			ConnectorRow(index: $0, connector: modified.connector(at: $0), isModified: modified.connector(at: $0) != original.connector(at: $0))
		})
		let connectorIndex = min(selectedConnector, modified.layout.connectorCount - 1)
		connectors.tableView.selectRowIndexes(IndexSet(integer: connectorIndex), byExtendingSelection: false)
		connectorFlags.show(modified.connector(at: connectorIndex).flags)
	}

	/// The display on this connector, as 4.x worked it out. With current patches applied, the
	/// display's port-number matches index + 4 (+ 3 on Sandy/Ivy Bridge, and 0 for the panel);
	/// otherwise its framebuffer index matches the row.
	private func attachedDisplay(_ row: ConnectorRow) -> Display? {
		let index = row.connector.index
		guard index != -1 else { return nil }
		let offset: UInt32 = [.sandyBridge, .ivyBridge].contains(model.generation) ? 3 : 4
		return model.displays.first { display in
			guard display.videoID & 0xFFFF == PCIVendor.intel else { return false }
			if Settings.applyCurrentPatches {
				return index == 0 ? display.port == 0 : UInt32(index) + offset == display.port
			}
			return UInt32(row.index) == display.index
		}
	}

	private func editConnector(_ row: ConnectorRow, _ change: (inout Connector) -> Void) {
		model.modify { framebuffer in
			var connector = framebuffer.connector(at: row.index)
			change(&connector)
			framebuffer.setConnector(connector, at: row.index)
		}
	}

	private func typePopUp(for row: ConnectorRow) -> NSView {
		let popUp = ConnectorTypePopUp(row: row.index, current: row.connector.type, target: self, action: #selector(typeChanged(_:)))
		popUp.controlSize = .small
		popUp.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		popUp.isBordered = false
		return popUp
	}

	@objc private func typeChanged(_ sender: ConnectorTypePopUp) {
		let type = UInt32(truncatingIfNeeded: sender.selectedTag())
		model.modify { framebuffer in
			var connector = framebuffer.connector(at: sender.row)
			connector.type = type
			framebuffer.setConnector(connector, at: sender.row)
		}
	}

	/// Swaps the selected connector with its neighbour (connector order matters to the framebuffer).
	private func moveConnector(by offset: Int) {
		guard let modified = model.modified else { return }
		let from = selectedConnector
		let to = from + offset
		guard (0..<modified.layout.connectorCount).contains(to) else { return }
		model.modify { framebuffer in
			let a = framebuffer.connector(at: from)
			let b = framebuffer.connector(at: to)
			framebuffer.setConnector(b, at: from)
			framebuffer.setConnector(a, at: to)
		}
		selectedConnector = to
		update()
	}

	@objc private func moveConnectorUp(_ sender: Any?) { moveConnector(by: -1) }
	@objc private func moveConnectorDown(_ sender: Any?) { moveConnector(by: 1) }

	@objc private func generationChanged(_ sender: NSPopUpButton) {
		guard let generation = IntelGeneration(rawValue: sender.indexOfSelectedItem) else { return }
		model.setGeneration(generation)
	}

	@objc private func platformChanged(_ sender: NSPopUpButton) {
		model.select(index: sender.indexOfSelectedItem)
	}

	@objc private func sourceChanged(_ sender: NSPopUpButton) {
		guard let source = FramebufferTable.Source(rawValue: sender.indexOfSelectedItem) else { return }
		model.setSource(source)
	}

	@objc private func reset(_ sender: Any?) {
		model.resetChanges()
	}

	var canRefresh: Bool { return true }
	func refresh() { model.load() }
	var searchPlaceholder: String? { return fields.searchPlaceholder }
	func search(_ text: String) { fields.search(text) }
}

final class ConnectorTypePopUp: NSPopUpButton {
	let row: Int

	init(row: Int, current: UInt32, target: AnyObject, action: Selector) {
		self.row = row
		super.init(frame: .zero, pullsDown: false)
		for type in ConnectorType.allCases {
			addItem(withTitle: L(type.name))
			lastItem?.tag = Int(type.rawValue)
		}
		if !selectItem(withTag: Int(current)) {
			addItem(withTitle: String(format: "0x%08X", current))
			lastItem?.tag = Int(current)
			select(lastItem)
		}
		self.target = target
		self.action = action
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}
}
