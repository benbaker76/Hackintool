//
//  FramebufferPatcher.swift
//  Hackintool
//
//  Turns edits to a framebuffer record into WhateverGreen DeviceProperties,
//  KextsToPatch find/replace pairs or an SSDT, and applies existing patches back.
//

import Foundation

/// Everything the patch output depends on, gathered once.
struct PatchContext {
	let table: FramebufferTable
	let index: Int
	let pciDevices: [PCIDevice]
	let audioDevices: [AudioDevice]
	let displays: [Display]
	/// The device ID chosen for "Inject Device ID", if any.
	let injectedDeviceID: UInt32?

	var original: Framebuffer { return table.original[index] }
	var modified: Framebuffer { return table.modified[index] }

	var platformID: UInt32 { return table.platformIDs[index] }

	func pciDevice(named name: String) -> PCIDevice? {
		return pciDevices.first { $0.acpiPath == name } ?? pciDevices.first { $0.acpiName == name }
	}

	var gpuDevice: PCIDevice? {
		if let igpu = pciDevice(named: "IGPU") {
			return igpu
		}
		return Settings.injectFakeIGPU ? PatchContext.fakeIGPU : nil
	}

	/// A stand-in IGPU at the usual address, for generating patches on a machine without one.
	static let fakeIGPU: PCIDevice = {
		var device = PCIDevice(fakeWithPath: "PciRoot(0x0)/Pci(0x2,0x0)", acpiPath: "/PCI0@0/IGPU@2", slotName: "Internal@0,2,0", address: 0x20000)
		device.deviceName = "Intel Graphics (Unknown)"
		device.className = "Display controller"
		device.subclassName = "VGA compatible controller"
		return device
	}()
}

extension PCIDevice {
	/// A placeholder device for patch generation.
	init(fakeWithPath devicePath: String, acpiPath: String, slotName: String, address: UInt32) {
		registryName = "IGPU"
		ioName = "display"
		servicePath = "IOService:/AppleACPIPlatformExpert/PCI0@0/AppleACPIPCI/IGPU@2"
		self.acpiPath = acpiPath
		self.devicePath = devicePath
		self.slotName = slotName
		vendorID = PCIVendor.intel
		deviceID = 0
		subsystemVendorID = 0
		subsystemID = 0
		classCode = 0x30000
		aspm = L("Disabled")
		model = nil
		bundleID = nil
		busDeviceFunction = "00:02.0"
		self.address = address
		shadowVendorID = PCIVendor.intel
		shadowDeviceID = 0
	}

	/// model, device_type and AAPL,slot-name — the basics every injected device gets.
	var basicProperties: [String: Any] {
		return [
			"model": deviceName,
			"device_type": subclassName == "???" ? className : subclassName,
			"AAPL,slot-name": slotName,
		]
	}
}

enum FramebufferPatcher {
	static let audioControllerNames = ["HDEF", "ALZA", "AZAL", "HDAS", "CAVS"]

	// MARK: DeviceProperties

	/// Adds IGPU, audio, PCI, hda-gfx and WLAN properties to `config`, per the patch settings.
	static func addDeviceProperties(to config: ConfigPlist, context: PatchContext, forceAll: Bool = false) {
		let properties = config.deviceProperties
		if Settings.patchGraphicDevice || forceAll, let gpu = context.gpuDevice {
			properties[gpu.devicePath] = igpuProperties(context: context, gpu: gpu)
		}
		if Settings.patchAudioDevice || forceAll {
			for name in audioControllerNames {
				guard let device = context.pciDevice(named: name) else { continue }
				properties[device.devicePath] = audioProperties(device, context: context)
			}
		}
		if Settings.patchPCIDevices || forceAll {
			for device in context.pciDevices {
				let existing = properties[device.devicePath] as? [String: Any] ?? [:]
				properties[device.devicePath] = existing.merging(device.basicProperties) { _, new in new }
			}
		}
		injectHDAGfx(into: properties, context: context)
		injectWLAN(into: properties, context: context)
	}

	static func igpuProperties(context: PatchContext, gpu: PCIDevice) -> NSMutableDictionary {
		let original = context.original
		let modified = context.modified
		let autoDetect = Settings.autoDetectChanges
		let properties = NSMutableDictionary(dictionary: gpu.basicProperties)
		func set(_ key: String, _ value: UInt32) { properties[key] = Data(littleEndian: value) }

		if context.table.kind == .sandyBridge {
			set("AAPL,snb-platform-id", context.platformID)
		} else {
			set("AAPL,ig-platform-id", modified.framebufferID ?? 0)
		}
		if Settings.gfxYTileFix { set("AAPL,GfxYTile", 1) }
		if Settings.injectDeviceID, let deviceID = context.injectedDeviceID { set("device-id", deviceID) }
		if Settings.disableeGPU { set("disable-external-gpu", 1) }
		if Settings.enableHDMI20 { set("enable-hdmi20", 1) }
		if Settings.hdmiInfiniteLoopFix { set("enable-hdmi-dividers-fix", 1) }
		if Settings.dpcdMaxLinkRateFix {
			let rates: [UInt32] = [0x06, 0x0A, 0x14, 0x1E]
			set("enable-dpcd-max-link-rate-fix", 1)
			set("dpcd-max-link-rate", rates[min(max(Settings.dpcdMaxLinkRate, 0), rates.count - 1)])
		}
		if Settings.patchEDID {
			for (index, display) in context.displays.enumerated() {
				if let edid = DisplayOverride.patchedEDID(for: display, settings: DisplaySettings(display: display)) {
					properties["AAPL0\(index),override-no-connect"] = edid.data
				}
			}
		}

		if !autoDetect || context.table.hasChanges(at: context.index) {
			set("framebuffer-patch-enable", 1)
		}

		// General fields.
		if autoDetect || Settings.patchAll {
			let changes: [(String, UInt32, UInt32)] = [
				("framebuffer-mobile", original.isMobile ? 1 : 0, modified.isMobile ? 1 : 0),
				("framebuffer-pipecount", original.pipeCount, modified.pipeCount),
				("framebuffer-portcount", original.portCount, modified.portCount),
				("framebuffer-memorycount", original.memoryCount, modified.memoryCount),
			] + (modified.flags == nil ? [] : [
				("framebuffer-flags", original.flags ?? 0, modified.flags ?? 0),
				("framebuffer-camellia", original.camellia ?? 0, modified.camellia ?? 0),
			])
			for (key, before, after) in changes where !autoDetect || before != after {
				set(key, after)
			}
		}

		// Memory.
		if (autoDetect || Settings.patchVRAM) && modified.stolenMemory != nil {
			let changes: [(String, UInt32?, UInt32?)] = [
				("framebuffer-stolenmem", original.stolenMemory, modified.stolenMemory),
				("framebuffer-fbmem", original.framebufferMemory, modified.framebufferMemory),
				("framebuffer-cursormem", original.cursorMemory, modified.cursorMemory),
				("framebuffer-unifiedmem", original.unifiedMemory, modified.unifiedMemory),
			]
			for (key, before, after) in changes {
				guard let after = after, !autoDetect || before != after else { continue }
				set(key, after)
			}
		}

		// Connectors.
		if autoDetect || Settings.patchConnectors {
			let count = modified.layout.connectorCount
			let changed = (0..<count).map { original.connector(at: $0) != modified.connector(at: $0) }
			if Settings.useAllDataMethod {
				// One "alldata" entry per run of consecutive changed connectors.
				var index = 0
				while index < count {
					guard changed[index] || !autoDetect else {
						index += 1
						continue
					}
					var run = 1
					while index + run < count && (changed[index + run] || !autoDetect) {
						run += 1
					}
					set("framebuffer-con\(index)-enable", 1)
					properties["framebuffer-con\(index)-alldata"] = Data(modified.connectorBytes(index, count: run))
					index += run
				}
			} else {
				for index in 0..<count where !autoDetect || changed[index] {
					let before = original.connector(at: index)
					let after = modified.connector(at: index)
					set("framebuffer-con\(index)-enable", 1)
					if !autoDetect || before.index != after.index { set("framebuffer-con\(index)-index", UInt32(bitPattern: after.index)) }
					if !autoDetect || before.busID != after.busID { set("framebuffer-con\(index)-busid", after.busID) }
					if !autoDetect || before.pipe != after.pipe { set("framebuffer-con\(index)-pipe", after.pipe) }
					if !autoDetect || before.type != after.type { set("framebuffer-con\(index)-type", after.type) }
					if !autoDetect || before.flags != after.flags { set("framebuffer-con\(index)-flags", after.flags) }
				}
			}
		}

		// LSPCON (HDMI 2.0 level shifters on some laptops).
		if Settings.lspconEnable {
			set("enable-lspcon-support", 1)
			let connectors = Settings.lspconAutoDetect
				? (0..<modified.layout.connectorCount).filter { modified.connector(at: $0).type == ConnectorType.hdmi.rawValue }
				: [Settings.lspconConnectorIndex]
			for index in connectors {
				set("framebuffer-con\(index)-has-lspcon", 1)
				if Settings.lspconPreferredMode {
					set("framebuffer-con\(index)-preferred-lspcon-mode", UInt32(Settings.lspconPreferredModeIndex))
				}
			}
		}
		return properties
	}

	static func audioProperties(_ device: PCIDevice, context: PatchContext) -> NSMutableDictionary {
		let properties = NSMutableDictionary(dictionary: device.basicProperties)
		if Settings.spoofAudioDeviceID {
			let controllerID = device.vendorID << 16 | device.deviceID
			if let spoof = (BundledData.intelSpoofAudio[String(format: "%08X", controllerID)] as? NSNumber)?.uint32Value {
				properties["device-id"] = Data(littleEndian: spoof)
			}
		}
		// The layout AppleALC is using on this controller.
		if let audio = context.audioDevices.first(where: { $0.isAppleHDA && $0.deviceID == device.vendorID << 16 | device.deviceID }) {
			properties["layout-id"] = Data(littleEndian: audio.alcLayoutID)
		}
		return properties
	}

	/// hda-gfx tells AppleHDA which GPU owns HDMI audio: Intel ("onboard-1") or a discrete GPU.
	static func injectHDAGfx(into properties: NSMutableDictionary, context: PatchContext) {
		let hasGFX0 = context.pciDevice(named: "GFX0") != nil
		func assign(_ name: String, intel: String?, discrete: String?) {
			guard let device = name == "IGPU" ? context.gpuDevice : context.pciDevice(named: name),
			      let entry = properties[device.devicePath] as? NSMutableDictionary else { return }
			if let value = Settings.useIntelHDMI ? intel : discrete {
				entry["hda-gfx"] = value
			}
		}
		assign("IGPU", intel: "onboard-1", discrete: hasGFX0 ? "onboard-2" : nil)
		assign("HDEF", intel: "onboard-1", discrete: hasGFX0 ? "onboard-2" : nil)
		assign("GFX0", intel: "onboard-2", discrete: "onboard-1")
		assign("HDAU", intel: "onboard-2", discrete: "onboard-1")
	}

	/// Dell DW1820A (BCM4350) needs to be presented as an Apple AirPort card.
	static func injectWLAN(into properties: NSMutableDictionary, context: PatchContext) {
		guard let wlan = context.pciDevices.first(where: { $0.classCode == 0x28000 }),
		      wlan.vendorID == 0x14E4, wlan.deviceID == 0x43A3,
		      [0x1028, 0x106B].contains(wlan.subsystemVendorID),
		      [0x0021, 0x0022, 0x0023, 0x075A].contains(wlan.subsystemID) else { return }
		properties[wlan.devicePath] = [
			"AAPL,slot-name": "WLAN",
			"compatible": "pci14e4,4331",
			"device_type": "Airport Extreme",
			"model": wlan.deviceName,
			"name": "Airport",
			"pci-aspm-default": 0,
		]
	}

	// MARK: KextsToPatch

	enum KextsToPatchFormat {
		case hex, base64
	}

	/// Find/replace pairs for the framebuffer kext, covering what changed.
	static func kextsToPatch(context: PatchContext, format: KextsToPatchFormat) -> String {
		let original = context.original.bytes
		let modified = context.modified.bytes
		let layout = context.modified.layout
		let words = layout.size / 4
		func word(_ bytes: [UInt8], _ index: Int) -> UInt32 {
			return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[index * 4 + $1]) << (8 * UInt32($1)) }
		}
		let changedWords = (0..<words).filter { word(original, $0) != word(modified, $0) }
		let connectorWords = (layout.connectorsOffset / 4, layout.connectorSize * layout.connectorCount)
		// The VRAM block starts at fMobile: counts, then stolen, fb (cursor on Haswell) and unified memory.
		let vramWords = (layout.mobile.offset / 4, context.table.kind == .haswell ? 20 : 16)
		let isSandyBridge = context.table.kind == .sandyBridge

		func hasChanges(_ range: (start: Int, bytes: Int)) -> Bool {
			return changedWords.contains { $0 >= range.start && $0 < range.start + range.bytes / 4 }
		}

		func entry(_ name: String, start: Int, bytes: Int) -> String {
			let byteRange = start * 4..<min(start * 4 + bytes, original.count)
			let find = Data(original[byteRange])
			let replace = Data(modified[byteRange])
			let findText: String
			let replaceText: String
			switch format {
			case .hex:
				// Shown as big-endian words, as the original tool did.
				func words(_ data: Data) -> String {
					return stride(from: 0, to: data.count, by: 4).map { offset in
						String(format: "%08X", data[data.startIndex + offset..<data.startIndex + min(offset + 4, data.count)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
					}.joined(separator: " ")
				}
				findText = words(find)
				replaceText = words(replace)
			case .base64:
				findText = find.base64EncodedString()
				replaceText = replace.base64EncodedString()
			}
			return "Find: \(findText)\nReplace: \(replaceText)\nComment: \(String(format: "0x%08X", context.platformID)) \(name) Patch by Hackintool (credit Ben Baker)\n\n"
		}

		var output = ""
		if Settings.autoDetectChanges {
			guard let first = changedWords.first, let last = changedWords.last else {
				return L("No Changes Detected!") + "\n"
			}
			if Settings.patchAll {
				let start = max(first - 1, 0)
				let end = min(last + 1, words - 1)
				output += entry("All", start: start, bytes: (end - start + 1) * 4)
			}
			if Settings.patchConnectors && hasChanges(connectorWords) {
				output += entry("Connector", start: connectorWords.0, bytes: connectorWords.1)
			}
			if !isSandyBridge && Settings.patchVRAM && hasChanges(vramWords) {
				output += entry("VRAM", start: vramWords.0, bytes: vramWords.1)
			}
		} else {
			output += entry("All", start: 0, bytes: layout.size)
			output += entry("Connector", start: connectorWords.0, bytes: connectorWords.1)
			if !isSandyBridge {
				output += entry("VRAM", start: vramWords.0, bytes: vramWords.1)
			}
		}
		return output
	}

	// MARK: SSDT

	/// An SSDT injecting the generated properties through _DSM, for setups without DeviceProperties.
	static func ssdt(context: PatchContext) -> String {
		let config = ConfigPlist(format: .openCore)
		addDeviceProperties(to: config, context: context)
		let properties = config.deviceProperties

		func device(_ pci: PCIDevice, tabs: Int) -> [String] {
			guard let entry = properties[pci.devicePath] as? [String: Any], let acpi = acpiPath(pci.acpiPath) else { return [] }
			let indent = String(repeating: "\t", count: tabs)
			var lines = [
				"\(indent)External (_SB_.\(acpi), DeviceObj)",
				"\(indent)Device (_SB.\(acpi))",
				"\(indent){",
				"\(indent)\tName (_ADR, \(String(format: "0x%08x", pci.address)))",
				"\(indent)\tMethod (_DSM, 4, NotSerialized)",
				"\(indent)\t{",
				"\(indent)\t\tIf (LEqual (Arg2, Zero)) { Return (Buffer() { 0x03 } ) }",
				"\(indent)\t\tReturn (Package ()",
				"\(indent)\t\t{",
			]
			for (key, value) in entry.sorted(by: { $0.key < $1.key }) {
				switch value {
				case let data as Data:
					lines.append("\(indent)\t\t\t\"\(key)\", Buffer () { \(data.hexString(delimiter: ", ", prefix: "0x")) },")
				case let string as String:
					lines.append("\(indent)\t\t\t\"\(key)\", Buffer () { \"\(string)\" },")
				default:
					continue
				}
			}
			lines += ["\(indent)\t\t})", "\(indent)\t}", "\(indent)}"]
			return lines
		}

		var lines: [String] = []
		if Settings.patchPCIDevices {
			lines.append("DefinitionBlock (\"\", \"SSDT\", 2, \"Hackintool\", \"PCI Devices\", 0x00000000)")
			lines.append("{")
			context.pciDevices.forEach { lines += device($0, tabs: 1) }
			lines.append("}")
		} else {
			if Settings.patchGraphicDevice, let gpu = context.gpuDevice {
				lines += device(gpu, tabs: 0)
			}
			if Settings.patchAudioDevice {
				audioControllerNames.compactMap(context.pciDevice(named:)).forEach { lines += device($0, tabs: 0) }
			}
		}
		return lines.joined(separator: "\n") + "\n"
	}

	/// "/PC00@0/RP01@1c/PXSX@0" → "PC00.RP01.PXSX"; nil if a component isn't a 4-character ACPI name.
	static func acpiPath(_ path: String) -> String? {
		let names = path.split(separator: "/").map { $0.split(separator: "@").first.map(String.init) ?? String($0) }
		guard !names.isEmpty, names.allSatisfy({ $0.count <= 4 }) else { return nil }
		return names.joined(separator: ".")
	}

	// MARK: Auto patching

	/// Applies the quick fixes (DVMT, VRAM, port limit, DP→HDMI, hotplug) to the modified record,
	/// and undoes any that are switched off.
	static func applyAutoPatches(to table: FramebufferTable, at index: Int) {
		let original = table.original[index]
		var modified = table.modified[index]

		if modified.stolenMemory != nil {
			modified.stolenMemory = Settings.dvmtPrealloc32MB ? 0x130_0000 : original.stolenMemory      // 19 MB
			modified.framebufferMemory = Settings.dvmtPrealloc32MB ? 0x90_0000 : original.framebufferMemory  // 9 MB
			modified.unifiedMemory = Settings.vram2048MB ? 0x8000_0000 : original.unifiedMemory   // 2048 MB
		}
		modified.portCount = Settings.fbPortLimit ? UInt32(Settings.fbPortCount) : original.portCount

		for connectorIndex in 0..<modified.layout.connectorCount {
			let before = original.connector(at: connectorIndex)
			var after = modified.connector(at: connectorIndex)
			let disablePort = Settings.fbPortLimit && connectorIndex >= Settings.fbPortCount
			if disablePort {
				after.index = -1
			} else {
				after.index = before.index
				after.type = Settings.dpToHDMI && before.type == ConnectorType.displayPort.rawValue ? ConnectorType.hdmi.rawValue : before.type
				after.pipe = Settings.hotplugRebootFix && after.index != -1 ? 18 : before.pipe
			}
			modified.setConnector(after, at: connectorIndex)
		}
		table.modified[index] = modified
	}

	// MARK: Applying existing patches

	/// Applies WhateverGreen framebuffer properties (from the running IGPU or a config.plist)
	/// to the modified record. Returns false if they're for a different platform ID.
	@discardableResult
	static func applyProperties(_ properties: [String: Any], to table: FramebufferTable, at index: Int) -> Bool {
		func number(_ key: String) -> UInt32? { return IOValue.uint32(properties[key]) }
		let platformID = table.platformIDs[index]
		applySettings(from: properties)

		guard number("framebuffer-patch-enable") == 1 else { return true }
		let propertyID = number("AAPL,snb-platform-id") ?? number("AAPL,ig-platform-id")
		guard propertyID == platformID else { return false }

		var record = table.modified[index]
		let layout = record.layout

		// framebuffer-patchN-find/replace, optionally restricted to a framebuffer ID.
		for patch in 0..<10 where number("framebuffer-patch\(patch)-enable") == 1 {
			if let id = number("framebuffer-patch\(patch)-framebufferid"), id != platformID { continue }
			guard let find = properties["framebuffer-patch\(patch)-find"] as? Data,
			      let replace = properties["framebuffer-patch\(patch)-replace"] as? Data else { continue }
			var bytes = Data(record.bytes)
			bytes.replaceOccurrences(of: find, with: replace, limit: Int(number("framebuffer-patch\(patch)-count") ?? 1))
			record.bytes = Array(bytes)
		}
		if let id = number("framebuffer-framebufferid"), id != platformID {
			table.modified[index] = record
			return true
		}

		func copy(_ key: String, into field: FramebufferLayout.Field?) {
			guard let field = field, let data = properties[key] as? Data else { return }
			for (offset, byte) in data.prefix(field.size).enumerated() {
				record.bytes[field.offset + offset] = byte
			}
		}
		copy("framebuffer-mobile", into: layout.mobile)
		copy("framebuffer-pipecount", into: layout.pipeCount)
		copy("framebuffer-portcount", into: layout.portCount)
		copy("framebuffer-memorycount", into: layout.memoryCount)
		copy("framebuffer-stolenmem", into: layout.stolenMemory)
		copy("framebuffer-fbmem", into: layout.framebufferMemory)
		copy("framebuffer-cursormem", into: layout.cursorMemory)
		copy("framebuffer-unifiedmem", into: layout.unifiedMemory)
		copy("framebuffer-flags", into: layout.flags)
		copy("framebuffer-camellia", into: layout.camellia)

		for connector in 0..<layout.connectorCount where number("framebuffer-con\(connector)-enable") == 1 {
			var value = record.connector(at: connector)
			if let index = number("framebuffer-con\(connector)-index") { value.index = Int32(bitPattern: index) }
			if let busID = number("framebuffer-con\(connector)-busid") { value.busID = busID }
			if let pipe = number("framebuffer-con\(connector)-pipe") { value.pipe = pipe }
			if let type = number("framebuffer-con\(connector)-type") { value.type = type }
			if let flags = number("framebuffer-con\(connector)-flags") { value.flags = flags }
			record.setConnector(value, at: connector)

			let allData = ["framebuffer-con\(connector)-alldata",
			               String(format: "framebuffer-con%d-%08X-alldata", connector, platformID),
			               String(format: "framebuffer-con%d-%08x-alldata", connector, platformID)]
			if let data = allData.lazy.compactMap({ properties[$0] as? Data }).first {
				let start = layout.connectorsOffset + connector * layout.connectorSize
				let end = min(start + data.count, layout.connectorsOffset + layout.connectorCount * layout.connectorSize)
				record.bytes.replaceSubrange(start..<end, with: data.prefix(end - start))
			}
		}
		table.modified[index] = record
		return true
	}

	/// Picks up the non-framebuffer options (eGPU, HDMI 2.0, LSPCON...) from existing properties.
	private static func applySettings(from properties: [String: Any]) {
		func number(_ key: String) -> UInt32? { return IOValue.uint32(properties[key]) }
		if number("device-id") != nil { Settings.injectDeviceID = true }
		if let value = number("disable-external-gpu") { Settings.disableeGPU = value != 0 }
		if let value = number("enable-hdmi20") { Settings.enableHDMI20 = value != 0 }
		if let value = number("AAPL,GfxYTile") { Settings.gfxYTileFix = value != 0 }
		if let value = number("enable-hdmi-dividers-fix") { Settings.hdmiInfiniteLoopFix = value != 0 }
		if let value = number("enable-lspcon-support") { Settings.lspconEnable = value != 0 }
		for connector in 0..<6 {
			if number("framebuffer-con\(connector)-has-lspcon") != nil {
				Settings.lspconAutoDetect = false
				Settings.lspconConnector = true
				Settings.lspconConnectorIndex = connector
			}
			if let mode = number("framebuffer-con\(connector)-preferred-lspcon-mode") {
				Settings.lspconPreferredMode = true
				Settings.lspconPreferredModeIndex = Int(mode)
			}
		}
	}
}
