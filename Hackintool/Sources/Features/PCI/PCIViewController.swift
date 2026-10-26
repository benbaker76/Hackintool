//
//  PCIViewController.swift
//  Hackintool
//
//  PCIe section: every PCI device with its IDs, names, class, ACPI and device paths.
//  The list refreshes when devices are hot-plugged.
//

import Cocoa

final class PCIViewController: NSViewController, SectionContent {
	private let table = DataTableViewController<PCIDevice>(columns: [
		DataColumn("PCIDebug", "Debug", width: 64, monospaced: true) { $0.busDeviceFunction },
		DataColumn.hex("VendorID", "Vendor", width: 64) { $0.vendorID },
		DataColumn.hex("DeviceID", "Device", width: 64) { $0.deviceID },
		DataColumn.hex("SubVendorID", "Sub Vendor", width: 76) { $0.subsystemVendorID },
		DataColumn.hex("SubDeviceID", "Sub Device", width: 76) { $0.subsystemID },
		DataColumn("ASPM", "ASPM", width: 60) { $0.aspm },
		DataColumn("VendorName", "Vendor Name", width: 150) { $0.vendorName },
		DataColumn("DeviceName", "Device Name", width: 220) { $0.deviceName },
		DataColumn("ClassName", "Class", width: 130) { $0.className },
		DataColumn("SubClassName", "Subclass", width: 130) { $0.subclassName },
		DataColumn("IORegName", "IOReg Name", width: 180) { $0.acpiPath },
		DataColumn("IORegIOName", "IOReg IOName", width: 110) { $0.ioName },
		DataColumn("DevicePath", "Device Path", width: 260, monospaced: true) { $0.devicePath },
		DataColumn("BundleID", "Kext", width: 220) { $0.bundleID ?? "" },
	])

	private var watcher: IOServiceWatcher?
	private let debouncer = Debouncer(delay: 0.5)

	override func loadView() {
		addChild(table)
		table.contextMenuItems = [
			menuItem("Copy IOReg Path", #selector(copyIORegPath(_:))),
			menuItem("Copy ACPI Path", #selector(copyACPIPath(_:))),
			menuItem("Copy Device Path", #selector(copyDevicePath(_:))),
			.separator(),
			menuItem("Show Kext in Finder", #selector(showKext(_:))),
		]
		table.onDoubleClick = { Kexts.reveal(bundleIdentifier: $0.bundleID) }

		let footer = ControlBar.make([], trailing: [
			ControlBar.button("Update PCI IDs", symbol: .import, target: self, action: #selector(updatePCIIDs(_:))),
			ControlBar.button("Export", symbol: .export, target: self, action: #selector(export(_:))),
		])
		view = ControlBar.stack(header: nil, content: table.view, footer: footer)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		refresh()
		watcher = IOServiceWatcher(className: "IOPCIDevice") { [weak self] _ in
			self?.debouncer.schedule { self?.refresh() }
		}
	}

	private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
		let item = NSMenuItem(title: L(title), action: action, keyEquivalent: "")
		item.target = self
		return item
	}

	// MARK: SectionContent

	var canRefresh: Bool { return true }

	func refresh() {
		DispatchQueue.global(qos: .userInitiated).async {
			let devices = PCIDevice.all()
			DispatchQueue.main.async { self.table.setRows(devices) }
		}
	}

	var searchPlaceholder: String? { return table.searchPlaceholder }
	func search(_ text: String) { table.search(text) }

	// MARK: Actions

	@objc private func copyIORegPath(_ sender: Any?) {
		Pasteboard.copy(table.targetRows.map { $0.servicePath }.joined(separator: "\n"))
	}

	@objc private func copyACPIPath(_ sender: Any?) {
		Pasteboard.copy(table.targetRows.map { $0.acpiPath }.joined(separator: "\n"))
	}

	@objc private func copyDevicePath(_ sender: Any?) {
		Pasteboard.copy(table.targetRows.map { $0.devicePath }.joined(separator: "\n"))
	}

	@objc private func showKext(_ sender: Any?) {
		Kexts.reveal(bundleIdentifier: table.targetRows.first?.bundleID)
	}

	@objc private func updatePCIIDs(_ sender: NSButton) {
		sender.isEnabled = false
		IDDatabase.pci.update { [weak self] success in
			sender.isEnabled = true
			if success {
				self?.refresh()
				Alerts.show("PCIIDs Update", "Successful!")
			} else {
				Alerts.error("PCIIDs Update", "Failure!")
			}
		}
	}

	@objc private func export(_ sender: Any?) {
		let devices = table.rows
		FilePanels.chooseFolder(prompt: "Export") { folder in
			var files = [
				("pcidevices.txt", PCIExport.table(devices)),
				("pcidevices.json", PCIExport.json(devices)),
			]
			// With a framebuffer table the plist and SSDT carry the full IGPU and audio properties too.
			let model = FramebufferModel()
			model.load()
			if let context = model.context {
				let config = ConfigPlist(format: BootloaderConfigFormat.current)
				FramebufferPatcher.addDeviceProperties(to: config, context: context, forceAll: true)
				files.append(("pcidevices.plist", config.xmlString))
				files.append(("pcidevices.dsl", FramebufferPatcher.ssdt(context: context, forceAll: true)))
			} else {
				files.append(("pcidevices.plist", PCIExport.deviceProperties(devices, format: BootloaderConfigFormat.current)))
			}
			FilePanels.write(files, to: folder)
		}
	}
}

/// Text, JSON and bootloader DeviceProperties renderings of the PCI device list.
enum PCIExport {
	static func table(_ devices: [PCIDevice]) -> String {
		func column(_ value: String, _ width: Int, alignRight: Bool = false, keepEnd: Bool = false) -> String {
			let clipped = keepEnd ? String(value.suffix(width)) : String(value.prefix(width))
			let padding = String(repeating: " ", count: max(0, width - clipped.count))
			return alignRight ? padding + clipped : clipped + padding
		}
		var lines = [
			"DEBUG   VID  DID  SVID SDID ASPM   Vendor Name                    Device Name                                        Class Name           SubClass Name        IOReg Name      IOReg IOName    Device Path",
			String(repeating: "-", count: 202),
		]
		for device in devices {
			lines.append([
				column(device.busDeviceFunction, 7),
				String(format: "%04X %04X %04X %04X", device.vendorID, device.deviceID, device.subsystemVendorID, device.subsystemID),
				column(device.aspm, 6),
				column(device.vendorName, 30),
				column(device.deviceName, 50),
				column(device.className, 20),
				column(device.subclassName, 20),
				column(device.acpiPath, 15, alignRight: true, keepEnd: true),
				column(device.ioName, 15),
				device.devicePath,
			].joined(separator: " "))
		}
		return lines.joined(separator: "\n") + "\n"
	}

	static func json(_ devices: [PCIDevice]) -> String {
		let array: [[String: Any]] = devices.map { device in
			var dictionary: [String: Any] = [
				"PCIDebug": device.busDeviceFunction,
				"VendorID": device.vendorID,
				"DeviceID": device.deviceID,
				"SubVendorID": device.subsystemVendorID,
				"SubDeviceID": device.subsystemID,
				"ShadowVendor": device.shadowVendorID,
				"ShadowDevice": device.shadowDeviceID,
				"ASPM": device.aspm,
				"ClassCode": device.classCode,
				"VendorName": device.vendorName,
				"DeviceName": device.deviceName,
				"ClassName": device.className,
				"SubClassName": device.subclassName,
				"IORegName": device.acpiPath,
				"IORegIOName": device.ioName,
				"IORegPath": device.servicePath,
				"DevicePath": device.devicePath,
				"SlotName": device.slotName,
				"Address": device.address,
				"Model": device.model ?? "???",
			]
			dictionary["BundleID"] = device.bundleID
			return dictionary
		}
		guard let data = try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted, .sortedKeys]) else { return "[]" }
		return String(decoding: data, as: UTF8.self)
	}

	/// model, device_type and AAPL,slot-name for every device, as config.plist DeviceProperties.
	static func deviceProperties(_ devices: [PCIDevice], format: BootloaderConfigFormat) -> String {
		var properties: [String: Any] = [:]
		for device in devices {
			properties[device.devicePath] = [
				"model": device.deviceName,
				"device_type": device.subclassName == "???" ? device.className : device.subclassName,
				"AAPL,slot-name": device.slotName,
			]
		}
		let config = format.wrapDeviceProperties(properties)
		guard let data = try? PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0) else { return "" }
		return String(decoding: data, as: UTF8.self)
	}
}
