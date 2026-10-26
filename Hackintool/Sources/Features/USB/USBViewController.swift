//
//  USBViewController.swift
//  Hackintool
//
//  USB section: map USB ports by plugging a device into each one. Active ports turn
//  green; name them, set their connector type, remove the ones you don't use and
//  export a USBPorts.kext.
//

import Cocoa

final class USBViewController: NSViewController, SectionContent {
	private let map = USBPortMap()

	private let controllers = DataTableViewController<USBController>(columns: [
		DataColumn("Type", "Type", width: 70) { $0.name },
		DataColumn("Name", "Name", width: 300) { $0.deviceName },
		DataColumn("Class", "Driver", width: 160) { $0.className },
		DataColumn.hex("ID", "Location", width: 70, digits: 2) { $0.location },
		DataColumn.hex("DeviceID", "Device ID", width: 90, digits: 8) { $0.deviceID },
	])

	private lazy var ports = DataTableViewController<USBPort>(columns: [
		DataColumn("UsbController", "Type", width: 70) { $0.isHubPort ? "\($0.controllerName) (Hub)" : $0.controllerName },
		DataColumn("name", "Name", width: 70, onEdit: { [weak self] port, value in
			self?.map.update(port) { $0.name = value }
		}) { $0.name },
		DataColumn.hex("locationID", "Location ID", width: 90, digits: 8) { $0.locationID },
		DataColumn.hex("port", "Port", width: 50, digits: 2) { $0.port },
		DataColumn("UsbConnector", "Connector", width: 140) { $0.connectorType?.name ?? String($0.connector) }
			.with(customView: { [unowned self] port in self.connectorPopUp(for: port) }),
		DataColumn("DevSpeed", "Dev Speed", width: 80) { $0.speedName },
		DataColumn("Device", "Device", width: 200) { $0.deviceName ?? "" },
		DataColumn("Comment", "Comment", width: 200, onEdit: { [weak self] port, value in
			self?.map.update(port) { $0.comment = value.isEmpty ? nil : value }
		}) { $0.comment ?? "" },
	])

	private let banner = NSTextField(wrappingLabelWithString: "")
	private lazy var renameButton = ControlBar.button("Add Renames…", symbol: .wand, target: self, action: #selector(addRenames(_:)))

	override func loadView() {
		addChild(controllers)
		addChild(ports)
		ports.rowColor = { port in
			port.deviceName != nil ? .systemGreen : (port.isActive ? .systemTeal : nil)
		}
		ports.contextMenuItems = [
			menuItem("Delete", #selector(deleteSelected(_:))),
		]

		banner.textColor = .systemOrange
		banner.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		let bannerBar = ControlBar.make([banner], trailing: [renameButton])

		let footer = ControlBar.make([
			ControlBar.button("Remove Unused", symbol: .trash, target: self, action: #selector(removeUnused(_:))),
			ControlBar.button("Delete", symbol: .remove, target: self, action: #selector(deleteSelected(_:))),
			ControlBar.button("Clear All", target: self, action: #selector(clearAll(_:))),
		], trailing: [
			ControlBar.button("Inject", symbol: .add, target: self, action: #selector(injectTemplate(_:))),
			ControlBar.button("Import", symbol: .import, target: self, action: #selector(importKext(_:))),
			ControlBar.button("Export", symbol: .export, target: self, action: #selector(export(_:))),
		])

		let split = NSSplitView()
		split.isVertical = false
		split.dividerStyle = .thin
		split.addArrangedSubview(controllers.view)
		split.addArrangedSubview(ControlBar.stack(header: bannerBar, content: ports.view, footer: footer))
		let controllersHeight = controllers.view.heightAnchor.constraint(equalToConstant: 120)
		controllersHeight.priority = .defaultLow
		controllersHeight.isActive = true
		view = split
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		map.onChange = { [weak self] in self?.reload() }
		map.refresh()
		map.startWatching()
	}

	private func reload() {
		controllers.setRows(map.controllers)
		ports.setRows(map.ports)
		updateBanner()
	}

	/// Warns about the 15-port limit, missing controllers and reserved ACPI names.
	private func updateBanner() {
		var messages: [String] = []
		if map.controllers.isEmpty {
			messages.append(L("No PCI USB controllers found. USB mapping applies to Intel and AMD Hackintosh systems."))
		}
		for (owner, count) in map.portCounts() where count > USBMapExport.portLimit {
			messages.append(L("%@ has %d ports; macOS uses at most %d per controller. Remove unused ports before exporting.", owner, count, USBMapExport.portLimit))
		}
		let renames = USBMapExport.neededRenames(map.controllers)
		if !renames.isEmpty {
			messages.append(L("Rename %@ so macOS doesn't apply its own port map.", renames.map { "\($0.from) → \($0.to)" }.joined(separator: ", ")))
		}
		messages.append(L("Plug a device into every port, in both orientations for Type-C. Ports turn green when in use."))
		banner.stringValue = messages.joined(separator: "\n")
		banner.textColor = messages.count > 1 ? .systemOrange : .secondaryLabelColor
		renameButton.isHidden = renames.isEmpty
	}

	private func connectorPopUp(for port: USBPort) -> NSView {
		let popUp = ConnectorPopUp(port: port, target: self, action: #selector(connectorChanged(_:)))
		popUp.controlSize = .small
		popUp.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		popUp.isBordered = false
		return popUp
	}

	@objc private func connectorChanged(_ sender: ConnectorPopUp) {
		guard let connector = sender.selectedConnector else { return }
		map.update(sender.port) { $0.connector = connector.rawValue }
	}

	private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
		let item = NSMenuItem(title: L(title), action: action, keyEquivalent: "")
		item.target = self
		return item
	}

	// MARK: SectionContent

	var canRefresh: Bool { return true }
	func refresh() { map.refresh() }
	var searchPlaceholder: String? { return ports.searchPlaceholder }
	func search(_ text: String) { ports.search(text) }

	// MARK: Actions

	@objc private func deleteSelected(_ sender: Any?) {
		map.remove(ports.targetRows)
	}

	@objc private func removeUnused(_ sender: Any?) {
		Alerts.confirm("Remove unused ports?", "Ports no device was plugged into while mapping will be removed from the map.", confirmTitle: "Remove") { confirmed in
			if confirmed {
				self.map.removeInactive()
			}
		}
	}

	@objc private func clearAll(_ sender: Any?) {
		Alerts.confirm("Clear the USB port map?", "Every port is removed; press Refresh to discover them again.", confirmTitle: "Clear") { confirmed in
			if confirmed {
				self.map.removeAll()
			}
		}
	}

	@objc private func injectTemplate(_ sender: Any?) {
		map.injectTemplatePorts()
	}

	@objc private func importKext(_ sender: Any?) {
		FilePanels.open(allowedExtensions: ["kext"]) { url in
			guard let imported = USBMapExport.importKext(at: url, controllers: self.map.controllers) else {
				Alerts.error("Couldn't read the kext.", url.path)
				return
			}
			self.map.replace(with: imported)
		}
	}

	@objc private func export(_ sender: Any?) {
		let overLimit = map.portCounts().filter { $0.count > USBMapExport.portLimit }
		let proceed = { (confirmed: Bool) in
			guard confirmed else { return }
			FilePanels.chooseFolder(prompt: "Export") { folder in
				do {
					let kext = try USBMapExport.writeKext(ports: self.map.ports, controllers: self.map.controllers, to: folder)
					let usbx = USBMapExport.ssdtUSBX()
					let aml = USBMapExport.compile(usbx.source, named: usbx.name, in: folder)
					NSWorkspace.shared.activateFileViewerSelecting([kext] + (aml.map { [$0] } ?? []))
				} catch {
					Alerts.error("Export Failed", error.localizedDescription)
				}
			}
		}
		if overLimit.isEmpty {
			proceed(true)
		} else {
			Alerts.confirm("Too many ports", L("%@ has more than %d ports. macOS will ignore the extra ports. Export anyway?", overLimit.map { $0.owner }.joined(separator: ", "), USBMapExport.portLimit), confirmTitle: "Export", completion: proceed)
		}
	}

	/// Exports SSDT-UIAC for setups still using USBInjectAll (Edit menu ▸ Export SSDT-UIAC).
	@objc func exportSSDTUIAC(_ sender: Any?) {
		FilePanels.chooseFolder(prompt: "Export") { folder in
			if let aml = USBMapExport.compile(USBMapExport.ssdtUIAC(ports: self.map.ports), named: "SSDT-UIAC", in: folder) {
				NSWorkspace.shared.activateFileViewerSelecting([aml])
			}
		}
	}

	@objc private func addRenames(_ sender: Any?) {
		let renames = USBMapExport.neededRenames(map.controllers)
		ConfigPlistPicker.choose { config, url in
			for rename in renames {
				config.addACPIRename(rename.from, to: rename.to)
			}
			do {
				try config.write(to: url)
				Alerts.show("Renames added.", "Reboot for the new controller names to take effect, then map your ports.")
			} catch {
				Alerts.error("Couldn't write the config.plist.", error.localizedDescription)
			}
		}
	}
}

/// A connector-type pop-up that remembers its port.
final class ConnectorPopUp: NSPopUpButton {
	let port: USBPort

	init(port: USBPort, target: AnyObject, action: Selector) {
		self.port = port
		super.init(frame: .zero, pullsDown: false)
		for connector in USBConnector.allCases {
			addItem(withTitle: L(connector.name))
			lastItem?.tag = Int(connector.rawValue)
		}
		if !selectItem(withTag: Int(port.connector)) {
			// Unknown values stay visible rather than being silently changed.
			addItem(withTitle: String(port.connector))
			lastItem?.tag = Int(port.connector)
			select(lastItem)
		}
		self.target = target
		self.action = action
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	var selectedConnector: USBConnector? {
		return USBConnector(rawValue: UInt8(truncatingIfNeeded: selectedTag()))
	}
}
