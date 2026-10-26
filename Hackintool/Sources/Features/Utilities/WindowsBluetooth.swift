//
//  WindowsBluetooth.swift
//  Hackintool
//
//  Exports macOS Bluetooth pairing keys as a Windows .reg file, so devices paired in
//  macOS also work in a dual-booted Windows without re-pairing.
//
//  macOS 12+ keeps the keys in the System keychain: classic devices under the
//  "MobileBluetooth" service (account = device address) and LE devices under
//  "BluetoothLE" (account = "Public <address>" or "Random <address>").
//  Earlier versions kept classic LinkKeys in root's bluetoothd preferences.
//

import Foundation

enum WindowsBluetooth {
	struct Export {
		let registryFile: String
		let deviceCount: Int
	}

	private static let keysPath = "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Services\\BTHPORT\\Parameters\\Keys"
	private static let header = "Windows Registry Editor Version 5.00\n\n"

	/// Builds the .reg contents. Asks for administrator rights once to read the keys.
	static func export() -> Export {
		if ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 12, minorVersion: 0, patchVersion: 0)) {
			return keychainExport()
		}
		let legacy = legacyLinkKeys("/private/var/root/Library/Preferences/com.apple.bluetoothd.plist")
			?? legacyLinkKeys("/private/var/root/Library/Preferences/blued.plist")
		return Export(registryFile: header + (legacy?.text ?? ""), deviceCount: legacy?.count ?? 0)
	}

	// MARK: macOS 12+

	private static func keychainExport() -> Export {
		guard let controller = controllerAddress().flatMap({ bytes($0, separator: ":") }) else {
			return Export(registryFile: header, deviceCount: 0)
		}

		// Every paired device has a keychain item, connected or not, so start from the
		// keychain rather than system_profiler (which lists connected devices separately on 13+).
		let items = keychainItems()
		let secrets = readSecrets(items)

		var output = header
		var count = 0
		var classicLines: [String] = []
		var classicLocalAddress: Data?

		for item in items where item.service == "MobileBluetooth" {
			guard let plist = secrets[item], let device = bytes(item.account, separator: ":"),
			      let linkKey = (plist["LinkKey"] as? String).flatMap({ bytes($0, separator: "-") }) else { continue }
			classicLocalAddress = (plist["LocalAddress"] as? String).flatMap { bytes($0, separator: ":") } ?? controller
			classicLines.append("\"\(hex(device))\"=hex:\(hex(linkKey, separator: ","))")
			count += 1
		}
		if let local = classicLocalAddress, !classicLines.isEmpty {
			output += "[\(keysPath)\\\(hex(local))]\n" + classicLines.joined(separator: "\n") + "\n"
		}

		// One LE entry per device: a public address if there is one, otherwise the random one.
		var exportedLE = Set<String>()
		for item in items.filter({ $0.service == "BluetoothLE" }).sorted(by: { $0.account.hasPrefix("Public") && !$1.account.hasPrefix("Public") }) {
			let parts = item.account.split(separator: " ", maxSplits: 1)
			guard parts.count == 2, !exportedLE.contains(String(parts[1])), let plist = secrets[item],
			      let device = bytes(String(parts[1]), separator: ":") else { continue }
			exportedLE.insert(String(parts[1]))
			output += lowEnergyEntry(plist, controller: controller, device: device, isPublic: parts[0] == "Public")
			count += 1
		}
		return Export(registryFile: output, deviceCount: count)
	}

	private static func controllerAddress() -> String? {
		guard let report = SystemProfiler.report("SPBluetoothDataType"),
		      let items = (report.first?["_items"] as? [[String: Any]])?.first else { return nil }
		return (items["controller_properties"] as? [String: Any])?["controller_address"] as? String
	}

	private static func lowEnergyEntry(_ plist: [String: Any], controller: Data, device: Data, isPublic: Bool) -> String {
		let encryption = plist["Remote Encryption"] as? [String: Any] ?? [:]
		var lines = ["", "[\(keysPath)\\\(hex(controller))\\\(hex(device))]"]
		if let ltk = encryption["Long-term Key"] as? Data {
			lines.append("\"LTK\"=hex:\(hex(ltk, separator: ","))")
		}
		let keyLength = (encryption["Long-term Key Length"] as? Data)?.littleEndianUInt32
			?? (encryption["Long-term Key Length"] as? NSNumber)?.uint32Value
			?? 0x10
		lines.append(String(format: "\"KeyLength\"=dword:%08x", keyLength))
		// LE Secure Connections pairings have no ERand/EDIV; Windows still expects zeros.
		let random = encryption["Random Number"] as? Data ?? Data(count: 8)
		lines.append("\"ERand\"=hex(b):\(hex(random, separator: ","))")
		let diversifier = (encryption["Encrypted Diversifier"] as? Data)?.littleEndianUInt32 ?? 0
		lines.append(String(format: "\"EDIV\"=dword:%08x", diversifier))
		let irk = plist["Remote IRK"] as? Data
		if let irk = irk {
			lines.append("\"IRK\"=hex:\(hex(Data(irk.reversed()), separator: ","))")
		}
		// Signing keys, written by newer bluetoothd for some BT 5 devices.
		if let localCSRK = (plist["Local CSRK"] as? Data) ?? (encryption["Local CSRK"] as? Data) {
			lines.append("\"CSRK\"=hex:\(hex(localCSRK, separator: ","))")
		}
		if let remoteCSRK = (plist["Remote CSRK"] as? Data) ?? (encryption["Remote CSRK"] as? Data) {
			lines.append("\"CSRKInbound\"=hex:\(hex(remoteCSRK, separator: ","))")
		}
		lines += [
			"\"Address\"=hex(b):\(hex(Data(device.reversed()) + Data([0, 0]), separator: ","))",
			String(format: "\"AddressType\"=dword:%08x", isPublic ? 0 : 1),
			String(format: "\"MasterIRKStatus\"=dword:%08x", irk != nil ? 1 : 0),
			"\"AuthReq\"=dword:0000002d",
		]
		return lines.joined(separator: "\n") + "\n"
	}

	// MARK: Keychain

	struct KeychainItem: Hashable {
		let service: String
		let account: String
	}

	/// Bluetooth items in the System keychain, listed without reading any secrets.
	static func keychainItems() -> [KeychainItem] {
		guard let result = Shell.run("/usr/bin/security", ["dump-keychain", "/Library/Keychains/System.keychain"]) else { return [] }
		var items: [KeychainItem] = []
		var account: String?
		var service: String?
		func flush() {
			if let account = account, let service = service, service == "MobileBluetooth" || service == "BluetoothLE" {
				items.append(KeychainItem(service: service, account: account))
			}
			account = nil
			service = nil
		}
		for line in result.output.split(separator: "\n") {
			if line.hasPrefix("keychain:") {
				flush()
			} else if let value = quotedValue(line, attribute: "\"acct\"") {
				account = value
			} else if let value = quotedValue(line, attribute: "\"svce\"") {
				service = value
			}
		}
		flush()
		return Array(Set(items)).sorted { $0.account < $1.account }
	}

	/// `"acct"<blob>="Public 18:4F:32:F4:0D:C8"` → the quoted value.
	private static func quotedValue(_ line: Substring, attribute: String) -> String? {
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		guard trimmed.hasPrefix(attribute), let start = trimmed.range(of: "=\"") else { return nil }
		return String(trimmed[start.upperBound...].dropLast())
	}

	/// Reads every item's secret in one privileged run (one password prompt), parsing
	/// each as a property list. Values print as hex, or as text when they're plain XML.
	private static func readSecrets(_ items: [KeychainItem]) -> [KeychainItem: [String: Any]] {
		guard !items.isEmpty else { return [:] }
		var script = ""
		for (index, item) in items.enumerated() {
			script += "echo '@@\(index)'; /usr/bin/security find-generic-password -a \(shellQuoted(item.account)) -s \(shellQuoted(item.service)) -w /Library/Keychains/System.keychain 2>/dev/null\n"
		}
		guard let result = Privileges.shared.run("/bin/sh", ["-c", script]) else { return [:] }

		var secrets: [KeychainItem: [String: Any]] = [:]
		var current: Int?
		var buffer = ""
		func flush() {
			defer { buffer = "" }
			guard let index = current, items.indices.contains(index) else { return }
			let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
			let data = text.hasPrefix("<?xml") ? text.data(using: .utf8) : Data(hexString: text)
			if let data = data, let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
				secrets[items[index]] = plist
			}
		}
		for line in result.output.components(separatedBy: "\n") {
			if line.hasPrefix("@@"), let index = Int(line.dropFirst(2)) {
				flush()
				current = index
			} else {
				buffer += line + "\n"
			}
		}
		flush()
		return secrets
	}

	private static func shellQuoted(_ value: String) -> String {
		return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}

	// MARK: macOS 10.13–11: LinkKeys in root's bluetoothd preferences

	private static func legacyLinkKeys(_ path: String) -> (text: String, count: Int)? {
		guard let result = Privileges.shared.run("/usr/bin/defaults", ["read", path, "LinkKeys"]), result.succeeded else { return nil }
		// `defaults` prints newer NSData as {length = n, bytes = 0x...}; turn it back into <...>.
		let text = result.output.replacingOccurrences(of: "\\{length = \\d+, bytes = 0x([0-9a-fA-F .]*)\\}", with: "<$1>", options: .regularExpression)
		guard let data = text.data(using: .utf8),
		      let linkKeys = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: [String: Data]] else { return nil }

		var output = ""
		var count = 0
		for (controller, devices) in linkKeys {
			output += "[\(keysPath)\\\(controller.replacingOccurrences(of: "-", with: ""))]\n"
			for (device, key) in devices {
				output += "\"\(device.replacingOccurrences(of: "-", with: ""))\"=hex:\(hex(Data(key.reversed()), separator: ","))\n"
				count += 1
			}
		}
		return (output, count)
	}

	// MARK: Helpers

	/// "18:4F:32:F3:41:D4" → bytes.
	private static func bytes(_ string: String, separator: Character) -> Data? {
		let values = string.split(separator: separator).compactMap { UInt8($0, radix: 16) }
		return values.count < 2 ? nil : Data(values)
	}

	private static func hex(_ data: Data, separator: String = "") -> String {
		return data.hexString(delimiter: separator, uppercase: false)
	}
}
