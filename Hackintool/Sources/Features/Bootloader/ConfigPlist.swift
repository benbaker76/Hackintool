//
//  ConfigPlist.swift
//  Hackintool
//
//  Reading and merging into Clover and OpenCore config.plist files.
//  Patches are added non-destructively: an identical existing patch is re-enabled
//  rather than duplicated, and the original file is backed up before writing.
//

import Cocoa
import DiskArbitration

final class ConfigPlist {
	let format: BootloaderConfigFormat
	/// The whole plist. NSMutableDictionary keeps nested in-place edits simple.
	let root: NSMutableDictionary

	init(format: BootloaderConfigFormat, root: NSMutableDictionary = NSMutableDictionary()) {
		self.format = format
		self.root = root
	}

	convenience init?(contentsOf url: URL, format: BootloaderConfigFormat) {
		guard let dictionary = NSMutableDictionary(contentsOf: url) else { return nil }
		self.init(format: format, root: ConfigPlist.deepMutableCopy(dictionary))
	}

	// MARK: Sections

	/// DeviceProperties ▸ Add (OpenCore) or Devices ▸ Properties (Clover), keyed by device path.
	var deviceProperties: NSMutableDictionary {
		switch format {
		case .openCore: return dictionary(at: ["DeviceProperties", "Add"])
		case .clover: return dictionary(at: ["Devices", "Properties"])
		}
	}

	/// DeviceProperties ▸ Delete (OpenCore only): device path → [property names].
	var devicePropertiesDelete: NSMutableDictionary {
		return dictionary(at: ["DeviceProperties", "Delete"])
	}

	/// Kernel ▸ Patch (OpenCore) or KernelAndKextPatches ▸ KextsToPatch / KernelToPatch (Clover).
	func kernelPatches(kernel: Bool = false) -> NSMutableArray {
		switch format {
		case .openCore: return array(at: ["Kernel", "Patch"])
		case .clover: return array(at: ["KernelAndKextPatches", kernel ? "KernelToPatch" : "KextsToPatch"])
		}
	}

	/// Kernel ▸ Quirks (OpenCore only).
	var kernelQuirks: NSMutableDictionary {
		return dictionary(at: ["Kernel", "Quirks"])
	}

	/// ACPI ▸ Patch (OpenCore) or ACPI ▸ DSDT ▸ Patches (Clover).
	var acpiPatches: NSMutableArray {
		switch format {
		case .openCore: return array(at: ["ACPI", "Patch"])
		case .clover: return array(at: ["ACPI", "DSDT", "Patches"])
		}
	}

	// MARK: Boot arguments

	/// The NVRAM GUID boot-args live under in OpenCore.
	static let appleBootVariableGUID = "7C436110-AB2A-4BBB-A880-FE41995C9F82"

	/// NVRAM ▸ Add ▸ 7C436110… ▸ boot-args (OpenCore) or Boot ▸ Arguments (Clover).
	var bootArgs: String {
		get {
			switch format {
			case .openCore: return dictionary(at: ["NVRAM", "Add", ConfigPlist.appleBootVariableGUID])["boot-args"] as? String ?? ""
			case .clover: return dictionary(at: ["Boot"])["Arguments"] as? String ?? ""
			}
		}
		set {
			switch format {
			case .openCore:
				dictionary(at: ["NVRAM", "Add", ConfigPlist.appleBootVariableGUID])["boot-args"] = newValue
				// OpenCore only overwrites a variable that's also listed under Delete.
				let delete = array(at: ["NVRAM", "Delete", ConfigPlist.appleBootVariableGUID])
				if !delete.contains("boot-args") {
					delete.add("boot-args")
				}
			case .clover:
				dictionary(at: ["Boot"])["Arguments"] = newValue
			}
		}
	}

	/// Adds boot arguments that aren't there yet; one with the same name ("radpg=7") is replaced in place.
	func addBootArgs(_ arguments: [String]) {
		guard !arguments.isEmpty else { return }
		func name(_ argument: String) -> String {
			return argument.split(separator: "=").first.map(String.init) ?? argument
		}
		var current = bootArgs.split(separator: " ").map(String.init)
		for argument in arguments {
			if let index = current.firstIndex(where: { name($0) == name(argument) }) {
				current[index] = argument
			} else {
				current.append(argument)
			}
		}
		bootArgs = current.joined(separator: " ")
	}

	// MARK: Adding patches

	/// Adds a kext or kernel patch written in Clover's format, converting it for OpenCore.
	/// Clover patches have Name, Comment, MatchOS, Find, Replace and optionally Disabled.
	func addKernelPatch(fromClover patch: [String: Any], kernel: Bool = false) {
		switch format {
		case .clover:
			var patch = patch
			patch.removeValue(forKey: "Type")
			add(patch, to: kernelPatches(kernel: kernel), matchingKeys: ["Find", "Replace", "Name", "MatchOS"], enable: ("Disabled", false))
		case .openCore:
			var converted: [String: Any] = [
				"Arch": "Any",
				"Base": "",
				"Comment": patch["Comment"] ?? "",
				"Count": 0,
				"Enabled": true,
				"Find": patch["Find"] ?? Data(),
				"Identifier": kernel ? "kernel" : (patch["Name"] ?? ""),
				"Limit": 0,
				"Mask": Data(),
				"MaxKernel": "",
				"MinKernel": "",
				"Replace": patch["Replace"] ?? Data(),
				"ReplaceMask": Data(),
				"Skip": 0,
			]
			if let matchOS = patch["MatchOS"] as? String {
				converted["MatchKernel"] = ConfigPlist.kernelPrefix(forMatchOS: matchOS) ?? ""
			}
			add(converted, to: kernelPatches(), matchingKeys: ["Find", "Replace", "Identifier", "MatchKernel"], enable: ("Enabled", true))
		}
	}

	/// Adds a DSDT find/replace patch (e.g. a device rename).
	func addACPIPatch(find: Data, replace: Data, comment: String) {
		switch format {
		case .clover:
			add(["Comment": comment, "Disabled": false, "Find": find, "Replace": replace],
			    to: acpiPatches, matchingKeys: ["Find", "Replace"], enable: ("Disabled", false))
		case .openCore:
			add(["Base": "", "BaseSkip": 0, "Comment": comment, "Count": 0, "Enabled": true, "Find": find,
			     "Limit": 0, "Mask": Data(), "OemTableId": Data(), "Replace": replace, "ReplaceMask": Data(),
			     "Skip": 0, "TableLength": 0, "TableSignature": "DSDT".data(using: .ascii)!],
			    to: acpiPatches, matchingKeys: ["Find", "Replace"], enable: ("Enabled", true))
		}
	}

	func addACPIRename(_ find: String, to replace: String) {
		addACPIPatch(find: find.data(using: .utf8)!, replace: replace.data(using: .utf8)!, comment: "Rename \(find) to \(replace)")
	}

	/// Appends `patch` unless an entry with equal values for `matchingKeys` exists, in which case that entry is enabled.
	private func add(_ patch: [String: Any], to array: NSMutableArray, matchingKeys: [String], enable: (key: String, value: Bool)) {
		for case let existing as NSMutableDictionary in array {
			let matches = matchingKeys.allSatisfy { key in
				(existing[key] as? NSObject) == (patch[key] as? NSObject)
			}
			if matches {
				existing[enable.key] = enable.value
				return
			}
		}
		array.add(NSMutableDictionary(dictionary: patch))
	}

	/// Darwin version prefix for a Clover MatchOS such as "10.14.x", "11.x", "26.x" or "27.x" → "18." / "20." / "25." / "27.".
	static func kernelPrefix(forMatchOS matchOS: String) -> String? {
		let parts = matchOS.split(separator: ".").compactMap { Int($0) }
		guard let major = parts.first else { return nil }
		switch major {
		case 10:
			guard parts.count > 1 else { return nil }
			return "\(parts[1] + 4)."      // 10.15 → Darwin 19
		case 11...15:
			return "\(major + 9)."         // 15 Sequoia → Darwin 24
		case 26:
			return "25."                     // 26 Tahoe → Darwin 25
		case 27...:
			return "\(major)."             // Darwin matches from 27 Golden Gate (Darwin 27)
		default:
			return nil
		}
	}

	/// Whether a Clover MatchOS ("10.15.x,11.x") includes the running macOS.
	static func matchesCurrentOS(_ matchOS: String?) -> Bool {
		guard let matchOS = matchOS else { return true }
		let version = ProcessInfo.processInfo.operatingSystemVersion
		return [
			"\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
			"\(version.majorVersion).\(version.minorVersion).x",
			"\(version.majorVersion).x.x",
			"\(version.majorVersion).x",
		].contains { matchOS.contains($0) }
	}

	// MARK: Writing

	/// Writes the plist, keeping a "-backup" copy of whatever was there (config-backup.plist).
	func write(to url: URL) throws {
		let fileManager = FileManager.default
		if fileManager.fileExists(atPath: url.path) {
			let backup = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-backup.plist")
			try? fileManager.removeItem(at: backup)
			try fileManager.copyItem(at: url, to: backup)
		}
		let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
		try data.write(to: url, options: .atomic)
	}

	var xmlString: String {
		guard let data = try? PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0) else { return "" }
		return String(decoding: data, as: UTF8.self)
	}

	// MARK: Helpers

	private func dictionary(at path: [String]) -> NSMutableDictionary {
		var current = root
		for key in path {
			if let next = current[key] as? NSMutableDictionary {
				current = next
			} else {
				let next = NSMutableDictionary()
				current[key] = next
				current = next
			}
		}
		return current
	}

	private func array(at path: [String]) -> NSMutableArray {
		let parent = dictionary(at: Array(path.dropLast()))
		if let existing = parent[path.last!] as? NSMutableArray {
			return existing
		}
		let array = NSMutableArray()
		parent[path.last!] = array
		return array
	}

	/// NSMutableDictionary(contentsOf:) only makes the top level mutable.
	static func deepMutableCopy(_ object: Any) -> NSMutableDictionary {
		func copy(_ value: Any) -> Any {
			switch value {
			case let dictionary as NSDictionary:
				let mutable = NSMutableDictionary()
				dictionary.forEach { mutable[$0.key] = copy($0.value) }
				return mutable
			case let array as NSArray:
				return NSMutableArray(array: array.map(copy))
			default:
				return value
			}
		}
		return copy(object) as? NSMutableDictionary ?? NSMutableDictionary()
	}
}

/// Choosing (and if necessary mounting) the config.plist to update.
enum ConfigPlistPicker {
	/// Mounts the boot EFI if needed, then asks the user which config.plist to update.
	/// A missing file can be created; an existing one is loaded.
	static func choose(completion: @escaping (ConfigPlist, URL) -> Void) {
		let format = BootloaderConfigFormat.current
		mountBootEFI { efiURL in
			let panel = NSSavePanel()
			panel.message = L("Please select your existing config.plist to overwrite.\nData is written non-destructively and a backup will be created first.")
			panel.nameFieldStringValue = "config.plist"
			panel.directoryURL = efiURL?.appendingPathComponent(format.efiDirectory)
			guard let window = NSApp.mainWindow else { return }
			panel.beginSheetModal(for: window) { response in
				guard response == .OK, let url = panel.url else { return }
				if FileManager.default.fileExists(atPath: url.path) {
					guard let config = ConfigPlist(contentsOf: url, format: format) else {
						Alerts.error("Couldn't read the config.plist.", url.path)
						return
					}
					completion(config, url)
				} else {
					Alerts.confirm(L("“%@” doesn't exist. Do you want to create it?", url.lastPathComponent), "", confirmTitle: "Create") { create in
						if create {
							completion(ConfigPlist(format: format), url)
						}
					}
				}
			}
		}
	}

	/// Calls back with the boot EFI's mount point, offering to mount it if it isn't mounted.
	static func mountBootEFI(completion: @escaping (URL?) -> Void) {
		guard let efi = BootEFI.partition() else {
			completion(nil)
			return
		}
		if let path = efi.volumePath {
			completion(path)
			return
		}
		Alerts.confirm("Mount Boot EFI Partition?", "Your Boot EFI Partition is not mounted.", confirmTitle: "Mount") { mount in
			guard mount else {
				completion(nil)
				return
			}
			efi.mount()
			completion(BootEFI.partition()?.volumePath)
		}
	}
}

/// A one-off lookup of the boot EFI partition, without a running DiskList.
enum BootEFI {
	static func partition() -> Disk? {
		guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
		let disks: [Disk] = IORegistryEntry.services(matching: "IOMedia").compactMap { media in
			guard let bsdName = media.string("BSD Name"),
			      let daDisk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName),
			      let description = DADiskCopyDescription(daDisk) as? [String: Any] else { return nil }
			return Disk(description: description)
		}
		guard let bootUUID = EFIBootDevice.mediaUUID, let bootDisk = disks.first(where: { $0.mediaUUID == bootUUID }) else {
			return nil
		}
		return bootDisk.isEFI ? bootDisk : disks.first { $0.isEFI && $0.wholeDiskName == bootDisk.wholeDiskName }
	}
}
