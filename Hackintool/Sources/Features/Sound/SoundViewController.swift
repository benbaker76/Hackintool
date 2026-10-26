//
//  SoundViewController.swift
//  Hackintool
//
//  Sound section: audio controllers and codecs, details of the selected one
//  (including AppleALC support), and its pin configuration.
//

import Cocoa

final class SoundViewController: NSViewController, SectionContent {
	private let devices = DataTableViewController<AudioDevice>(columns: [
		DataColumn.hex("Device", "Device", width: 90, digits: 8) { $0.deviceID },
		DataColumn.hex("SubDevice", "Sub Device", width: 90, digits: 8) { $0.subDeviceID },
		DataColumn.hex("Codec", "Codec", width: 90, digits: 8) { $0.codecID },
		DataColumn.hex("Revision", "Revision", width: 80, digits: 6) { $0.codecRevisionID },
		DataColumn("Name", "Name", width: 320) { "\($0.codecVendorName) \($0.codecName)" },
		DataColumn("BundleID", "Kext", width: 220) { $0.bundleID ?? "" },
	])
	private let info = PropertyListViewController(showsGroupHeaders: false)
	private let pins = DataTableViewController<PinNode>(columns: [
		DataColumn("Color", "", width: 22) { $0.colorName }
			.with(customView: { JackColorView(color: $0.jackColor) }),
		DataColumn("Node", "Node", width: 70, monospaced: true, sortKey: { .number(Double($0.nid)) }) { $0.nodeName },
		DataColumn("PinDefault", "Pin Default", width: 80, monospaced: true) { String(format: "%08X", $0.pinDefault) },
		DataColumn("Direction", "Direction", width: 60) { $0.direction },
		DataColumn("Device", "Device", width: 120) { $0.deviceName },
		DataColumn("Connector", "Connector", width: 120) { $0.connectorName },
		DataColumn("Port", "Port", width: 90) { $0.portName },
		DataColumn("GrossLocation", "Gross Location", width: 90) { $0.grossLocationName },
		DataColumn("Location", "Location", width: 90) { $0.locationName },
		DataColumn("ColorName", "Color", width: 70) { $0.colorName },
		DataColumn("Group", "Group", width: 50, sortKey: { .number(Double($0.group)) }) { String($0.group) },
		DataColumn("Index", "Index", width: 50, sortKey: { .number(Double($0.index)) }) { String($0.index) },
		DataColumn("EAPD", "EAPD", width: 50) { $0.hasEAPD ? String(format: "0x%1X", $0.eapd) : "-" },
	])

	override func loadView() {
		[devices, info, pins].forEach(addChild)
		devices.tableView.allowsMultipleSelection = false
		devices.onSelectionChange = { [weak self] rows in self?.show(rows.first) }
		devices.onDoubleClick = { Kexts.reveal(bundleIdentifier: $0.bundleID) }

		let bottom = NSSplitView()
		bottom.isVertical = true
		bottom.dividerStyle = .thin
		bottom.addArrangedSubview(info.view)
		bottom.addArrangedSubview(ControlBar.stack(header: ControlBar.make([ControlBar.heading("Pin Configuration")]), content: pins.view))
		let infoWidth = info.view.widthAnchor.constraint(equalToConstant: 340)
		infoWidth.priority = .defaultLow
		infoWidth.isActive = true

		let split = NSSplitView()
		split.isVertical = false
		split.dividerStyle = .thin
		split.addArrangedSubview(devices.view)
		split.addArrangedSubview(bottom)
		let devicesHeight = devices.view.heightAnchor.constraint(equalToConstant: 150)
		devicesHeight.priority = .defaultLow
		devicesHeight.isActive = true
		view = split
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		refresh()
	}

	private func show(_ device: AudioDevice?) {
		guard let device = device else {
			info.setItems([])
			pins.setRows([])
			return
		}
		info.setItems(SoundViewController.details(of: device))
		pins.setRows(device.pinNodes)
	}

	static func details(of device: AudioDevice) -> [PropertyItem] {
		var items = [
			PropertyItem("Class", device.deviceClass),
			PropertyItem("Vendor", String(format: "%@ (0x%04X)", device.vendorName, device.deviceID >> 16)),
			PropertyItem("Device", String(format: "%@ (0x%04X)%@", device.deviceName, device.deviceID & 0xFFFF, device.spoofDeviceID != nil ? "*" : "")),
		]
		if device.spoofDeviceID != nil {
			items.append(PropertyItem("", "* " + L("You may require Spoof Audio Device ID")))
		}
		items += [
			PropertyItem("Sub Vendor", String(format: "%@ (0x%04X)", device.subVendorName, device.subDeviceID >> 16)),
			PropertyItem("Sub Device", String(format: "%@ (0x%04X)", device.subDeviceName, device.subDeviceID & 0xFFFF)),
		]
		if device.audioDeviceModelID != 0 {
			items.append(PropertyItem("Audio Vendor", String(format: "%@ (0x%04X)", device.audioDeviceManufacturerName ?? "???", device.audioDeviceModelID >> 16)))
			items.append(PropertyItem("Audio Device", String(format: "%@ (0x%04X)", device.audioDeviceName ?? "???", device.audioDeviceModelID & 0xFFFF)))
		}
		if device.codecID != 0 {
			items.append(PropertyItem("Codec Vendor", String(format: "%@ (0x%04X)", device.codecVendorName, device.codecID >> 16)))
			items.append(PropertyItem("Codec Name", String(format: "%@ (0x%04X)", device.codecName, device.codecID & 0xFFFF)))
			if device.isAppleHDA {
				items += [
					PropertyItem("ALC Layout ID", String(device.alcLayoutID)),
					PropertyItem("Layout IDs", device.supportedLayoutIDs.map(String.init).joined(separator: " ")),
					PropertyItem("Revisions", device.supportedRevisions.joined(separator: " ")),
					PropertyItem("Min Kernel", String(device.minKernel)),
					PropertyItem("Max Kernel", String(device.maxKernel)),
				]
			}
		}
		if let config = device.hdaConfigDefault {
			func data(_ key: String) -> String? { return (config[key] as? Data)?.classicHexString }
			func number(_ key: String) -> NSNumber? { return config[key] as? NSNumber }
			let entries: [(String, String?)] = [
				("AFG Low Power State", data("AFGLowPowerState")),
				("Codec ID", number("CodecID").map { String(format: "0x%04X", $0.uint32Value) }),
				("Config Data", data("ConfigData")),
				("Func Group", number("FuncGroup")?.stringValue),
				("Codec", config["Codec"] as? String),
				("Wake Verb Reinit", (config["WakeVerbReinit"] as? Bool).map { L($0 ? "Yes" : "No") }),
				("Layout ID", number("LayoutID")?.stringValue),
				("Boot Config Data", data("BootConfigData")),
			]
			items += entries.compactMap { name, value in value.map { PropertyItem(name, $0) } }
		}
		return items
	}

	// MARK: SectionContent

	var canRefresh: Bool { return true }

	func refresh() {
		DispatchQueue.global(qos: .userInitiated).async {
			let all = AudioDevice.all()
			DispatchQueue.main.async {
				self.devices.setRows(all)
				// Select the AppleHDA device, as that's the one AppleALC drives.
				let preferred = self.devices.visibleRows.firstIndex { $0.isAppleHDA } ?? 0
				if !all.isEmpty {
					self.devices.tableView.selectRowIndexes(IndexSet(integer: preferred), byExtendingSelection: false)
				} else {
					self.show(nil)
				}
			}
		}
	}

	var searchPlaceholder: String? { return pins.searchPlaceholder }
	func search(_ text: String) { pins.search(text) }
}

/// A round swatch showing a jack's colour.
final class JackColorView: NSView {
	private let color: NSColor?

	init(color: NSColor?) {
		self.color = color
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	override func draw(_ dirtyRect: NSRect) {
		guard let color = color else { return }
		let size: CGFloat = 12
		let rect = NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)
		let circle = NSBezierPath(ovalIn: rect)
		color.setFill()
		circle.fill()
		if #available(macOS 10.14, *) {
			NSColor.separatorColor.setStroke()
		} else {
			NSColor.gridColor.setStroke()
		}
		circle.lineWidth = 1
		circle.stroke()
	}
}
