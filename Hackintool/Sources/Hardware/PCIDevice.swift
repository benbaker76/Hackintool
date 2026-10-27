//
//  PCIDevice.swift
//  Hackintool
//
//  PCI devices from the I/O Registry, with names from pci.ids and their
//  ACPI path, EFI device path and slot name.
//

import Foundation

enum PCIVendor {
	static let amd: UInt32 = 0x1002
	static let intel: UInt32 = 0x8086
	static let nvidia: UInt32 = 0x10DE
}

struct PCIDevice {
	/// The registry name ("IGPU", "HDEF", "pci8086,1234").
	let registryName: String
	/// IOName, e.g. "display" for GPUs.
	let ioName: String
	/// IOService plane path.
	let servicePath: String
	/// e.g. "/PC00@0/PEG0@1/PEGP@0".
	let acpiPath: String
	/// e.g. "PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)".
	let devicePath: String
	/// e.g. "Internal@0,1,0/0,0".
	let slotName: String

	let vendorID: UInt32
	let deviceID: UInt32
	let subsystemVendorID: UInt32
	let subsystemID: UInt32
	let classCode: UInt32
	let aspm: String
	let model: String?
	let bundleID: String?
	/// Bus:device.function from "pcidebug", e.g. "00:02.0".
	let busDeviceFunction: String
	/// (device << 16) | function within the parent bus.
	let address: UInt32
	/// IDs from a "pciVVVV,DDDD" name, which reveal a spoofed device ID.
	let shadowVendorID: UInt32
	let shadowDeviceID: UInt32

	var vendorName = "???"
	var deviceName = "???"
	var className = "???"
	var subclassName = "???"

	var isDisplay: Bool { return ioName == "display" }

	/// An icon for the device's PCI class.
	var symbol: Symbol {
		switch (classCode >> 16, classCode >> 8 & 0xFF) {
		case (0x03, _): return .gpu
		case (0x04, _): return .sound
		case (0x02, 0x80): return .wifi
		case (0x02, _): return .network
		case (0x01, _): return .storage
		case (0x0C, 0x03): return .usb
		case (0x06, 0x04), (0x06, 0x00): return .bridge
		case (0x07, 0x80): return .shieldLock
		default: return .cpu
		}
	}

	/// (device << 16) | vendor, as used in framebuffer and audio patches.
	var combinedID: UInt32 { return deviceID << 16 | vendorID }

	/// The last component of the ACPI path ("PEGP"), the name to use in patches.
	var acpiName: String {
		let last = acpiPath.split(separator: "/").last.map(String.init) ?? registryName
		return last.split(separator: "@").first.map(String.init) ?? last
	}
}

extension PCIDevice {
	/// All PCI devices currently in the I/O Registry.
	static func all() -> [PCIDevice] {
		#if DEBUG
		if SampleData.isEnabled { return SampleData.pciDevices }
		#endif
		let database = IDDatabase.pci
		return IORegistryEntry.services(matching: "IOPCIDevice").compactMap { entry -> PCIDevice? in
			guard let device = PCIDevice(entry: entry) else { return nil }
			return device.named(using: database)
		}
	}

	init?(entry: IORegistryEntry) {
		guard let servicePath = entry.path() else { return nil }
		let properties = entry.properties
		let name = entry.name
		let ioName = IOValue.string(properties["IOName"]) ?? IOValue.string(properties["name"]) ?? "???"
		let shadowID = PCIDevice.shadowID(fromName: ioName)

		registryName = name
		self.ioName = ioName
		self.servicePath = servicePath
		vendorID = IOValue.uint32(properties["vendor-id"]) ?? 0
		deviceID = IOValue.uint32(properties["device-id"]) ?? 0
		subsystemVendorID = IOValue.uint32(properties["subsystem-vendor-id"]) ?? 0
		subsystemID = IOValue.uint32(properties["subsystem-id"]) ?? 0
		classCode = IOValue.uint32(properties["class-code"]) ?? 0
		aspm = PCIDevice.aspmDescription(IOValue.uint32(properties["pci-aspm-default"]) ?? 0)
		model = IOValue.string(properties["model"])
		bundleID = (entry.searchProperty("CFBundleIdentifier", parents: false) ?? entry.searchProperty("CFBundleIdentifier")) as? String
		busDeviceFunction = PCIDevice.busDeviceFunction(fromPCIDebug: properties["pcidebug"] as? String)
		shadowVendorID = shadowID.map { $0 & 0xFFFF } ?? vendorID
		shadowDeviceID = shadowID.map { $0 >> 16 } ?? deviceID

		let location = PCIDevice.location(of: entry)
		address = location.device << 16 | location.function

		var acpiPath = location.hasFunction ? String(format: "%@@%X,%X", name, location.device, location.function) : String(format: "%@@%X", name, location.device)
		var devicePath = String(format: "Pci(0x%X,0x%X)", location.device, location.function)
		var slotName = "\(location.device),\(location.function)"

		// Walk up through parent bridges, nearest first.
		for parent in entry.ancestors() where parent.conforms(to: "IOPCIDevice") {
			let parentLocation = PCIDevice.location(of: parent)
			acpiPath = (parentLocation.hasFunction
				? String(format: "%@@%X,%X/", parent.name, parentLocation.device, parentLocation.function)
				: String(format: "%@@%X/", parent.name, parentLocation.device)) + acpiPath
			devicePath = String(format: "Pci(0x%X,0x%X)/", parentLocation.device, parentLocation.function) + devicePath
			slotName = "\(parentLocation.device),\(parentLocation.function)/" + slotName
		}

		// The root bridge is an ACPI device such as PNP0A03 / PNP0A08.
		if let root = entry.ancestor(conformingTo: ["IOACPIPlatformDevice"]) {
			let pnp = IOValue.string(root.property("compatible")) ?? IOValue.string(root.property("name")) ?? ""
			let uid = UInt32(IOValue.string(root.property("_UID")) ?? "") ?? 0
			devicePath = PCIDevice.acpiDevicePath(pnp: pnp, uid: uid) + "/" + devicePath
			acpiPath = "/\(root.name)@\(uid)/" + acpiPath
			slotName = "Internal@\(uid)," + slotName
		}

		self.acpiPath = acpiPath
		self.devicePath = devicePath
		self.slotName = slotName
	}

	func named(using database: IDDatabase) -> PCIDevice {
		var device = self
		device.vendorName = database.vendorName(vendorID) ?? "???"
		device.deviceName = database.deviceName(vendorID: vendorID, deviceID: deviceID) ?? "???"
		let names = database.className(classCode: classCode)
		device.className = names.className ?? "???"
		device.subclassName = names.subclassName ?? "???"

		// Intel Power Gadget requires the GPU "model" to start with "Intel".
		if vendorID == PCIVendor.intel && isDisplay && !device.deviceName.hasPrefix("Intel") {
			device.deviceName = "Intel " + device.deviceName
		}
		return device
	}

	// MARK: Parsing helpers

	/// "pci8086,9b41" → (0x9b41 << 16) | 0x8086.
	static func shadowID(fromName name: String) -> UInt32? {
		guard name.hasPrefix("pci"), name.contains(",") else { return nil }
		let parts = name.dropFirst(3).split(separator: ",")
		guard parts.count == 2, let vendor = UInt32(parts[0], radix: 16), let device = UInt32(parts[1], radix: 16) else { return nil }
		return device << 16 | vendor
	}

	/// "pcidebug" looks like "0:2:0" or "0:28:4(1:1)" (bus:device:function(secondary:subordinate)).
	static func busDeviceFunction(fromPCIDebug pciDebug: String?) -> String {
		let numbers = (pciDebug ?? "").split(whereSeparator: { ":()".contains($0) }).compactMap { Int($0) }
		guard numbers.count >= 3 else { return "00:00.0" }
		return String(format: "%02X:%02X.%X", numbers[0], numbers[1], numbers[2])
	}

	/// The device and function numbers from an entry's location ("1c,4").
	static func location(of entry: IORegistryEntry) -> (device: UInt32, function: UInt32, hasFunction: Bool) {
		let parts = (entry.location() ?? "").split(separator: ",")
		let device = parts.first.flatMap { UInt32($0, radix: 16) } ?? 0
		let function = parts.count > 1 ? UInt32(parts[1], radix: 16) ?? 0 : 0
		return (device, function, parts.count > 1)
	}

	/// The EFI device path node for an ACPI root bridge, from its PNP ID (e.g. "PNP0A08").
	static func acpiDevicePath(pnp: String, uid: UInt32) -> String {
		let characters = Array(pnp.utf8)
		guard characters.count > 3 else { return String(format: "Acpi(0x00000000,0x%X)", uid) }
		let pnpNumber = UInt32(String(decoding: characters[3...], as: UTF8.self), radix: 16) ?? 0
		let compressed = (UInt32(characters[0] &- 0x40) & 0x1F) << 10 | (UInt32(characters[1] &- 0x40) & 0x1F) << 5 | (UInt32(characters[2] &- 0x40) & 0x1F)
		let eisaID = compressed + (pnpNumber << 16)

		// EISA IDs with the "PNP" prefix encode to 0x41D0.
		guard eisaID & 0xFFFF == 0x41D0 else {
			return String(format: "Acpi(0x%08X,0x%X)", eisaID, uid)
		}
		let number = eisaID >> 16
		if number == 0x0A03 {
			return String(format: "PciRoot(0x%X)", uid)
		}
		return String(format: "Acpi(PNP%04X,0x%X)", number, uid)
	}

	/// PCIe Active State Power Management: 0 off, 1 L0s, 2 L1, 3 both.
	static func aspmDescription(_ aspm: UInt32) -> String {
		return [L("Disabled"), "L0s", "L1", "L0s+L1"][Int(aspm & 0x3)]
	}
}
