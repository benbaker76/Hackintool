//
//  Display.swift
//  Hackintool
//
//  Connected displays (IODisplay services) and the GPU framebuffer port each is on.
//

import Cocoa
import IOKit.graphics

struct Display {
	var name: String
	/// The framebuffer index on its GPU.
	let index: UInt32
	/// The framebuffer's "port-number".
	let port: UInt32
	let vendorID: UInt32
	let productID: UInt32
	let serialNumber: UInt32
	let edid: Data?
	let prefsKey: String?
	let isInternal: Bool
	/// IOService path of the GPU (IOPCIDevice) driving the display.
	let videoPath: String?
	/// (device << 16) | vendor of that GPU.
	let videoID: UInt32
	let displayID: CGDirectDisplayID?

	/// All displays known to the I/O Registry.
	static func all() -> [Display] {
		#if DEBUG
		if SampleData.isEnabled { return SampleData.displays }
		#endif
		let activeDisplays = Display.activeDisplayIDs()
		return IORegistryEntry.services(matching: "IODisplay").compactMap { entry in
			guard let framebuffer = entry.ancestor(conformingTo: ["IOFramebuffer"]),
			      let gpu = entry.ancestor(conformingTo: ["IOPCIDevice"]) else { return nil }

			let info = IODisplayCreateInfoDictionary(entry.raw, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any] ?? [:]
			let names = info[kDisplayProductName] as? [String: String]
			let vendorID = (info[kDisplayVendorID] as? NSNumber)?.uint32Value ?? 0
			let productID = (info[kDisplayProductID] as? NSNumber)?.uint32Value ?? 0
			let serialNumber = (info[kDisplaySerialNumber] as? NSNumber)?.uint32Value ?? 0
			let gpuVendor = gpu.uint32("vendor-id") ?? 0
			let gpuDevice = gpu.uint32("device-id") ?? 0
			// AMD hangs the IOFramebuffer (AMDFramebufferVIB) under ATY,AMD,RadeonFramebuffer@N,
			// which carries the index and port-number, so look up to the GPU for them.
			let ports = [framebuffer] + framebuffer.ancestors().prefix { $0.registryID != gpu.registryID }
			let index = ports.lazy.compactMap { $0.location().flatMap { UInt32($0) } }.first ?? 0
			let port = ports.lazy.compactMap { $0.uint32("port-number") }.first ?? 0

			let displayID = activeDisplays.first {
				CGDisplayVendorNumber($0) == vendorID && CGDisplayModelNumber($0) == productID && CGDisplaySerialNumber($0) == serialNumber
			}

			return Display(name: names?.values.first ?? L("Unknown"),
			               index: index,
			               port: port,
			               vendorID: vendorID,
			               productID: productID,
			               serialNumber: serialNumber,
			               edid: info["IODisplayEDID"] as? Data,
			               prefsKey: info["IODisplayPrefsKey"] as? String,
			               isInternal: entry.name == "AppleBacklightDisplay",
			               videoPath: gpu.path(),
			               videoID: gpuDevice << 16 | gpuVendor,
			               displayID: displayID)
		}
	}

	static func activeDisplayIDs() -> [CGDirectDisplayID] {
		var count: UInt32 = 0
		guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
		var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
		guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
		return Array(displays.prefix(Int(count)))
	}
}
