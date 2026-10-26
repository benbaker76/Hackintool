//
//  WindowsBluetooth.swift
//  Hackintool
//
//  Exports macOS Bluetooth pairing keys as a Windows .reg file, so devices paired in
//  macOS also work in a dual-booted Windows without re-pairing.
//

import Foundation

enum WindowsBluetooth {
	private static let keysPath = "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Services\\BTHPORT\\Parameters\\Keys"

	/// Builds the .reg contents. Needs administrator rights before macOS 12 (keys were in root's preferences).
	static func registryFile() -> String {
		var output = "Windows Registry Editor Version 5.00\n\n"
		if ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 12, minorVersion: 0, patchVersion: 0)) {
			output += keychainKeys()
		} else {
			output += legacyLinkKeys("/private/var/root/Library/Preferences/com.apple.bluetoothd.plist")
				?? legacyLinkKeys("/private/var/root/Library/Preferences/blued.plist")
				?? ""
		}
		return output
	}

	// MARK: macOS 12+: keys live in the keychain

	private static func keychainKeys() -> String {
		guard let report = SystemProfiler.report("SPBluetoothDataType"),
		      let items = (report.first?["_items"] as? [[String: Any]])?.first,
		      let controllerAddress = (items["controller_properties"] as? [String: Any])?["controller_address"] as? String,
		      let controllerData = bytes(controllerAddress, separator: ":") else { return "" }

		let devices = (items["devices_list"] ?? items["device_not_connected"]) as? [[String: Any]] ?? []
		var output = ""
		for device in devices {
			guard let properties = device.values.first as? [String: Any],
			      let address = properties["device_address"] as? String,
			      let addressData = bytes(address, separator: ":") else { continue }

			// Classic Bluetooth: LinkKey and LocalAddress in the "MobileBluetooth" item.
			if let plist = keychainPlist(account: address, service: "MobileBluetooth"),
			   let linkKey = (plist["LinkKey"] as? String).flatMap({ bytes($0, separator: "-") }),
			   let localAddress = (plist["LocalAddress"] as? String).flatMap({ bytes($0, separator: ":") }) {
				output += "[\(keysPath)\\\(hex(localAddress))]\n"
				output += "\"\(hex(addressData))\"=hex:\(hex(linkKey, separator: ","))\n"
			}

			// Bluetooth LE: keys in "BluetoothLE" items, under public or random addresses.
			for account in ["Public \(address)", "Random \(address)"] {
				if let plist = keychainPlist(account: account, service: "BluetoothLE") {
					output += lowEnergyEntry(plist, controller: controllerData, device: addressData)
				}
			}
		}
		return output
	}

	private static func lowEnergyEntry(_ plist: [String: Any], controller: Data, device: Data) -> String {
		let encryption = plist["Remote Encryption"] as? [String: Any] ?? [:]
		var lines = ["", "[\(keysPath)\\\(hex(controller))\\\(hex(device))]"]
		if let ltk = encryption["Long-term Key"] as? Data {
			lines.append("\"LTK\"=hex:\(hex(ltk, separator: ","))")
		}
		if let length = encryption["Long-term Key Length"] as? Data {
			lines.append(String(format: "\"KeyLength\"=dword:%08x", length.littleEndianUInt32))
		}
		if let random = encryption["Random Number"] as? Data {
			lines.append("\"ERand\"=hex(b):\(hex(random, separator: ","))")
		}
		if let diversifier = encryption["Encrypted Diversifier"] as? Data {
			lines.append(String(format: "\"EDIV\"=dword:%08x", diversifier.littleEndianUInt32))
		}
		if let irk = plist["Remote IRK"] as? Data {
			lines.append("\"IRK\"=hex:\(hex(Data(irk.reversed()), separator: ","))")
		}
		lines += [
			"\"Address\"=hex(b):\(hex(Data(device.reversed()) + Data([0, 0]), separator: ","))",
			"\"AddressType\"=dword:00000001",
			"\"MasterIRKStatus\"=dword:00000001",
			"\"AuthReq\"=dword:0000002d",
		]
		return lines.joined(separator: "\n") + "\n"
	}

	/// The hex-encoded plist stored as a generic password.
	private static func keychainPlist(account: String, service: String) -> [String: Any]? {
		guard let output = Shell.run("/usr/bin/security", ["find-generic-password", "-a", account, "-s", service, "-w"]),
		      output.succeeded,
		      let data = Data(hexString: output.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
		return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
	}

	// MARK: macOS 10.13–11: LinkKeys in root's bluetoothd preferences

	private static func legacyLinkKeys(_ path: String) -> String? {
		guard let result = Privileges.shared.run("/usr/bin/defaults", ["read", path, "LinkKeys"]), result.succeeded else { return nil }
		// `defaults` prints newer NSData as {length = n, bytes = 0x...}; turn it back into <...>.
		let text = result.output.replacingOccurrences(of: "\\{length = \\d+, bytes = 0x([0-9a-fA-F .]*)\\}", with: "<$1>", options: .regularExpression)
		guard let data = text.data(using: .utf8),
		      let linkKeys = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: [String: Data]] else { return nil }

		var output = ""
		for (controller, devices) in linkKeys {
			output += "[\(keysPath)\\\(controller.replacingOccurrences(of: "-", with: ""))]\n"
			for (device, key) in devices {
				output += "\"\(device.replacingOccurrences(of: "-", with: ""))\"=hex:\(hex(Data(key.reversed()), separator: ","))\n"
			}
		}
		return output
	}

	// MARK: Helpers

	/// "18:4F:32:F3:41:D4" → bytes.
	private static func bytes(_ string: String, separator: Character) -> Data? {
		let values = string.split(separator: separator).compactMap { UInt8($0, radix: 16) }
		return values.isEmpty ? nil : Data(values)
	}

	private static func hex(_ data: Data, separator: String = "") -> String {
		return data.hexString(delimiter: separator, uppercase: false)
	}
}
