//
//  Peripherals.swift
//  Hackintool
//
//  Network, Bluetooth, graphics and storage devices and the drivers serving them.
//

import Foundation

struct NetworkInterface {
	let bsdName: String
	let isBuiltIn: Bool
	let vendorID: UInt32
	let deviceID: UInt32
	let vendorName: String
	let deviceName: String
	let bundleID: String?

	static func all() -> [NetworkInterface] {
		let database = IDDatabase.pci
		return IORegistryEntry.services(matching: "IONetworkInterface").compactMap { entry in
			guard let pci = entry.ancestor(conformingTo: ["IOPCIDevice"]) else { return nil }
			let vendorID = pci.uint32("vendor-id") ?? 0
			let deviceID = pci.uint32("device-id") ?? 0
			return NetworkInterface(bsdName: entry.string("BSD Name") ?? "???",
			                        isBuiltIn: (entry.property("IOBuiltin") as? Bool) ?? false,
			                        vendorID: vendorID,
			                        deviceID: deviceID,
			                        vendorName: database.vendorName(vendorID) ?? "???",
			                        deviceName: database.deviceName(vendorID: vendorID, deviceID: deviceID) ?? "???",
			                        bundleID: entry.searchProperty("CFBundleIdentifier") as? String)
		}
	}
}

struct BluetoothDevice {
	let vendorID: UInt32
	let deviceID: UInt32
	let vendorName: String
	let deviceName: String
	let isFirmwareLoaded: Bool
	let bundleID = "com.apple.iokit.IOBluetoothHostControllerTransport"

	/// USB Bluetooth controllers found through their transport driver, then through ports
	/// owned by bluetoothd, then (native Apple hardware) through system_profiler.
	static func all() -> [BluetoothDevice] {
		let viaTransport = IORegistryEntry.services(matching: "IOBluetoothHostControllerTransport").compactMap {
			$0.ancestor(conformingTo: usbDeviceClasses)
		}
		if !viaTransport.isEmpty {
			return viaTransport.map(BluetoothDevice.init(usbDevice:))
		}

		let viaPorts = devicesOwnedByBluetoothd()
		if !viaPorts.isEmpty {
			return viaPorts.map(BluetoothDevice.init(usbDevice:))
		}

		return nativeController().map { [$0] } ?? []
	}

	static let usbDeviceClasses = ["IOUSBHostDevice", "IOUSBDevice"]

	init(vendorID: UInt32, deviceID: UInt32, vendorName: String, deviceName: String, isFirmwareLoaded: Bool) {
		self.vendorID = vendorID
		self.deviceID = deviceID
		self.vendorName = vendorName
		self.deviceName = deviceName
		self.isFirmwareLoaded = isFirmwareLoaded
	}

	init(usbDevice entry: IORegistryEntry) {
		let properties = entry.properties
		// Some firmware loaders publish PCI-style IDs that override the USB ones.
		let vendorID = IOValue.uint32(properties["vendor-id"]).flatMap { $0 == 0 ? nil : $0 } ?? IOValue.uint32(properties["idVendor"]) ?? 0
		let deviceID = IOValue.uint32(properties["device-id"]).flatMap { $0 == 0 ? nil : $0 } ?? IOValue.uint32(properties["idProduct"]) ?? 0
		let database = IDDatabase.usb
		self.init(vendorID: vendorID,
		          deviceID: deviceID,
		          vendorName: database.vendorName(vendorID) ?? properties["USB Vendor Name"] as? String ?? "???",
		          deviceName: database.deviceName(vendorID: vendorID, deviceID: deviceID) ?? properties["USB Product Name"] as? String ?? "???",
		          isFirmwareLoaded: (properties["FirmwareLoaded"] ?? properties["RM,FirmwareLoaded"]) as? Bool ?? false)
	}

	/// USB devices with a user client owned by bluetoothd (other than Apple's own host controller).
	private static func devicesOwnedByBluetoothd() -> [IORegistryEntry] {
		return IORegistryEntry.services(matching: "AppleUSBHostPort").compactMap { port in
			guard !port.conforms(to: "AppleUSBHubPort"),
			      let client = port.descendant(conformingTo: ["IOUserClient"]),
			      client.string("UsbUserClientOwningTaskName") == "bluetoothd",
			      let device = client.ancestor(conformingTo: usbDeviceClasses),
			      device.string("USB Product Name") != "Bluetooth USB Host Controller" else { return nil }
			return device
		}
	}

	/// Apple's built-in controller as reported by system_profiler.
	private static func nativeController() -> BluetoothDevice? {
		guard let report = SystemProfiler.report("SPBluetoothDataType"),
		      let controller = (report.first?["_items"] as? [[String: Any]])?.first?["controller_properties"] as? [String: Any] else { return nil }

		var device = BluetoothDevice(vendorID: SystemProfiler.hexID(controller["controller_vendorID"]),
		                             deviceID: SystemProfiler.hexID(controller["controller_productID"]),
		                             vendorName: "Apple",
		                             deviceName: controller["controller_chipset"] as? String ?? "???",
		                             isFirmwareLoaded: true)

		// The USB report, matched by serial (the controller address), has better names.
		let serial = (controller["controller_address"] as? String)?.replacingOccurrences(of: ":", with: "")
		if let serial = serial, let usbDevice = SystemProfiler.usbDevices().first(where: { $0["serial_num"] as? String == serial }) {
			device = BluetoothDevice(vendorID: SystemProfiler.hexID(usbDevice["vendor_id"]),
			                         deviceID: SystemProfiler.hexID(usbDevice["product_id"]),
			                         vendorName: usbDevice["manufacturer"] as? String ?? device.vendorName,
			                         deviceName: usbDevice["_name"] as? String ?? device.deviceName,
			                         isFirmwareLoaded: true)
		}
		return device
	}
}

struct GraphicsDevice {
	let model: String
	/// The platform ID for Intel, otherwise the framebuffer's name.
	let framebuffer: String
	let portCount: Int
	let bundleID: String?

	/// One entry per GPU, counting the framebuffers (ports) each drives.
	static func all() -> [GraphicsDevice] {
		var devices: [GraphicsDevice] = []
		var indexByModel: [String: Int] = [:]
		for framebuffer in IORegistryEntry.services(matching: "IOFramebuffer") {
			guard let gpu = framebuffer.ancestor(conformingTo: ["IOPCIDevice"]) else { continue }
			let model = gpu.string("model") ?? "???"
			if let index = indexByModel[model] {
				let existing = devices[index]
				devices[index] = GraphicsDevice(model: model, framebuffer: existing.framebuffer, portCount: existing.portCount + 1, bundleID: existing.bundleID)
				continue
			}
			let platformID = gpu.uint32("AAPL,snb-platform-id").flatMap { $0 == 0 ? nil : $0 } ?? gpu.uint32("AAPL,ig-platform-id")
			indexByModel[model] = devices.count
			devices.append(GraphicsDevice(model: model,
			                              framebuffer: platformID.map { $0.hex8 } ?? framebuffer.name,
			                              portCount: 1,
			                              bundleID: gpu.searchProperty("CFBundleIdentifier", parents: false) as? String))
		}
		return devices
	}
}

struct StorageDevice {
	let model: String
	let type: String
	let location: String
	let blockSize: Int?
	let bundleID: String?

	static func all() -> [StorageDevice] {
		return IORegistryEntry.services(matching: "IOBlockStorageDevice").map { entry in
			let properties = entry.properties
			let device = properties["Device Characteristics"] as? [String: Any] ?? [:]
			let protocolInfo = properties["Protocol Characteristics"] as? [String: Any] ?? [:]
			let blockSize = (properties["Physical Block Size"] ?? device["Physical Block Size"]) as? NSNumber
			return StorageDevice(model: (device["Product Name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "???",
			                     type: protocolInfo["Physical Interconnect"] as? String ?? "???",
			                     location: protocolInfo["Physical Interconnect Location"] as? String ?? "???",
			                     blockSize: blockSize?.intValue,
			                     bundleID: entry.searchProperty("CFBundleIdentifier") as? String)
		}
	}
}

/// Reading system_profiler's XML reports.
enum SystemProfiler {
	static func report(_ dataType: String) -> [[String: Any]]? {
		guard let output = Shell.run("/usr/sbin/system_profiler", [dataType, "-xml", "-timeout", "5"])?.output,
		      let data = output.data(using: .utf8),
		      let report = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]],
		      !report.isEmpty else { return nil }
		return report
	}

	/// Every USB device, flattened. macOS 26 renamed SPUSBDataType to SPUSBHostDataType.
	static func usbDevices() -> [[String: Any]] {
		guard let report = report("SPUSBHostDataType") ?? report("SPUSBDataType") else { return [] }
		func flatten(_ items: [[String: Any]]) -> [[String: Any]] {
			return items.flatMap { [$0] + flatten($0["_items"] as? [[String: Any]] ?? []) }
		}
		return flatten(report.first?["_items"] as? [[String: Any]] ?? [])
	}

	/// "0x05ac  (Apple Inc.)" → 0x05ac.
	static func hexID(_ value: Any?) -> UInt32 {
		guard let string = value as? String else { return 0 }
		let token = string.split(separator: " ").first.map(String.init) ?? string
		return UInt32(token.lowercased().replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0
	}
}
