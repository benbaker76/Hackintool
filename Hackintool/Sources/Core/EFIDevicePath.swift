//
//  EFIDevicePath.swift
//  Hackintool
//
//  Converts binary EFI device paths to text using GfxUtil's C parser.
//

import Foundation

enum EFIDevicePath {
	/// Text for a hard-drive device path node, e.g. the boot partition's GPT GUID.
	static func text(forHardDrivePath data: Data) -> String? {
		return data.withUnsafeBytes { buffer -> String? in
			guard let base = buffer.baseAddress else { return nil }
			guard let text = ConvertHDDDevicePathToText(base.assumingMemoryBound(to: EFI_DEVICE_PATH.self)) else { return nil }
			defer { free(text) }
			return String(cString: text)
		}
	}

	/// Full text for a device path, e.g. "PciRoot(0x0)/Pci(0x1F,0x3)".
	static func text(for data: Data) -> String? {
		return data.withUnsafeBytes { buffer -> String? in
			guard let base = buffer.baseAddress else { return nil }
			guard let text = ConvertDevicePathToText(base.assumingMemoryBound(to: EFI_DEVICE_PATH.self), 1, 1) else { return nil }
			defer { free(text) }
			return String(cString: text)
		}
	}

	/// The EFI device path of the device-tree entry whose path contains `search` (e.g. "HDEF").
	static func path(forDeviceTreeEntry search: String) -> String? {
		guard let root = IORegistryEntry.root else { return nil }
		var iterator: io_iterator_t = 0
		guard IORegistryEntryCreateIterator(root.raw, IORegistryEntry.Plane.deviceTree.rawValue, 0, &iterator) == KERN_SUCCESS else { return nil }
		defer { IOObjectRelease(iterator) }

		var devicePath: UnsafeMutablePointer<EFI_DEVICE_PATH>?
		var match: BOOLEAN = 0
		_ = RecursiveFindDevicePath(iterator, search, IORegistryEntry.Plane.deviceTree.rawValue, &devicePath, &match)
		guard let path = devicePath else { return nil }
		defer { free(path) }
		guard match != 0, let text = ConvertDevicePathToText(path, 1, 1) else { return nil }
		defer { free(text) }
		return String(cString: text)
	}
}
