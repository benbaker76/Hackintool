//
//  PeripheralsViewController.swift
//  Hackintool
//
//  System ▸ Peripherals: network, Bluetooth, graphics and storage devices
//  and the drivers attached to them.
//

import Cocoa

final class PeripheralsViewController: NSViewController, SectionContent {
	private let network = DataTableViewController<NetworkInterface>(columns: [
		DataColumn("BSDName", "BSD Name", width: 80) { $0.bsdName },
		DataColumn("BuiltIn", "Built In", width: 60) { L($0.isBuiltIn ? "Yes" : "No") },
		DataColumn.hex("VendorID", "Vendor ID") { $0.vendorID },
		DataColumn.hex("DeviceID", "Device ID") { $0.deviceID },
		DataColumn("VendorName", "Vendor Name", width: 160) { $0.vendorName },
		DataColumn("DeviceName", "Device Name", width: 220) { $0.deviceName },
		DataColumn("BundleID", "Kext", width: 220) { $0.bundleID ?? "" },
	])

	private let bluetooth = DataTableViewController<BluetoothDevice>(columns: [
		DataColumn.hex("VendorID", "Vendor ID") { $0.vendorID },
		DataColumn.hex("DeviceID", "Device ID") { $0.deviceID },
		DataColumn("VendorName", "Vendor Name", width: 160) { $0.vendorName },
		DataColumn("DeviceName", "Device Name", width: 220) { $0.deviceName },
		DataColumn("FWLoaded", "FW Loaded", width: 80) { L($0.isFirmwareLoaded ? "Yes" : "No") },
		DataColumn("BundleID", "Kext", width: 220) { $0.bundleID },
	])

	private let graphics = DataTableViewController<GraphicsDevice>(columns: [
		DataColumn("Model", "Model", width: 220) { $0.model },
		DataColumn("Framebuffer", "Framebuffer", width: 140) { $0.framebuffer },
		DataColumn("PortCount", "Port Count", width: 80, sortKey: { .number(Double($0.portCount)) }) { String($0.portCount) },
		DataColumn("BundleID", "Kext", width: 220) { $0.bundleID ?? "" },
	])

	private let storage = DataTableViewController<StorageDevice>(columns: [
		DataColumn("Model", "Model", width: 220) { $0.model },
		DataColumn("Type", "Type", width: 100) { $0.type },
		DataColumn("Location", "Location", width: 100) { $0.location },
		DataColumn("BlockSize", "Block Size", width: 80, sortKey: { .number(Double($0.blockSize ?? 0)) }) { $0.blockSize.map(String.init) ?? "" },
		DataColumn("BundleID", "Kext", width: 220) { $0.bundleID ?? "" },
	])

	private lazy var stacked = StackedTablesViewController(panes: [
		.init(title: "Network", viewController: network),
		.init(title: "Bluetooth", viewController: bluetooth),
		.init(title: "Graphics", viewController: graphics),
		.init(title: "Storage", viewController: storage),
	])

	override func loadView() {
		addChild(stacked)
		view = stacked.view
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		refresh()
	}

	var canRefresh: Bool { return true }

	func refresh() {
		DispatchQueue.global(qos: .userInitiated).async {
			let networkInterfaces = NetworkInterface.all()
			let bluetoothDevices = BluetoothDevice.all()
			let graphicsDevices = GraphicsDevice.all()
			let storageDevices = StorageDevice.all()
			DispatchQueue.main.async {
				self.network.setRows(networkInterfaces)
				self.bluetooth.setRows(bluetoothDevices)
				self.graphics.setRows(graphicsDevices)
				self.storage.setRows(storageDevices)
			}
		}
	}

	var searchPlaceholder: String? { return stacked.searchPlaceholder }
	func search(_ text: String) { stacked.search(text) }
}
