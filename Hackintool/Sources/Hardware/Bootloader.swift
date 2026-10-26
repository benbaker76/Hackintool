//
//  Bootloader.swift
//  Hackintool
//
//  Detecting the running bootloader and its version, and the config.plist
//  layout each one uses.
//

import Foundation

enum Bootloader {
	case clover(bootedRevision: String, installedRevision: String?)
	case openCore(bootedVersion: String)

	/// The bootloader that started this boot, if either left its marks in NVRAM.
	static let detected: Bootloader? = detect()

	private static func detect() -> Bootloader? {
		// Clover first: OpenCore never sets clovergui-revision, but Clover can publish an
		// opencore-version that looks real.
		if let revision = cloverRevision() {
			return .clover(bootedRevision: revision, installedRevision: cloverInstalledRevision())
		}
		if let version = openCoreVersion() {
			return .openCore(bootedVersion: version)
		}
		return nil
	}

	/// e.g. "0.9.8" from opencore-version "REL-098-2024-02-05".
	static func openCoreVersion() -> String? {
		guard let data = IORegistryEntry(path: "IODeviceTree:/options")?.data("4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version"),
		      data.count >= 18, let value = String(data: data.prefix(18), encoding: .ascii) else { return nil }
		// Clover publishes a placeholder value.
		guard value != "UNK-000-0000-00-00" else { return nil }
		let digits = Array(value.dropFirst(4).prefix(3))
		guard digits.count == 3 else { return nil }
		return "\(digits[0]).\(digits[1]).\(digits[2])"
	}

	static func cloverRevision() -> String? {
		guard let data = IORegistryEntry(path: "IODeviceTree:/efi/platform")?.data("clovergui-revision") else { return nil }
		return String(data.littleEndianUInt32)
	}

	/// The revision the Clover installer last installed.
	static func cloverInstalledRevision() -> String? {
		let url = URL(fileURLWithPath: "/Library/Preferences/com.projectosx.clover.installer.plist")
		guard let dictionary = NSDictionary(contentsOf: url) else { return nil }
		return (dictionary["CloverRevision"] as? NSNumber)?.stringValue
	}

	var isOpenCore: Bool {
		if case .openCore = self { return true }
		return false
	}
}

/// How config.plist sections differ between bootloaders.
enum BootloaderConfigFormat {
	case clover
	case openCore

	/// Follows the user's choice in settings, falling back to the detected bootloader
	/// (and OpenCore when neither is known).
	static var current: BootloaderConfigFormat {
		switch Settings.selectedBootloader {
		case .clover: return .clover
		case .openCore: return .openCore
		case .autoDetect:
			if case .clover? = Bootloader.detected {
				return .clover
			}
			return .openCore
		}
	}

	/// Wraps DeviceProperties entries (keyed by device path) in the right config.plist structure.
	func wrapDeviceProperties(_ properties: [String: Any]) -> [String: Any] {
		switch self {
		case .clover: return ["Devices": ["Properties": properties]]
		case .openCore: return ["DeviceProperties": ["Add": properties]]
		}
	}

	/// The EFI folder that holds config.plist.
	var efiDirectory: String {
		switch self {
		case .clover: return "EFI/CLOVER"
		case .openCore: return "EFI/OC"
		}
	}
}
