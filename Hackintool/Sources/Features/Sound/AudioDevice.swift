//
//  AudioDevice.swift
//  Hackintool
//
//  Audio devices (IOAudioDevice under each PCI controller) with their HDA codec,
//  AppleALC layout and the codec's pin configuration.
//

import Cocoa

struct AudioDevice {
	/// The driver class, e.g. "AppleHDADriver".
	let deviceClass: String
	let bundleID: String?
	/// Controller: (vendor << 16) | device.
	let deviceID: UInt32
	let subDeviceID: UInt32
	let revisionID: UInt32
	let alcLayoutID: UInt32
	let audioDeviceName: String?
	let audioDeviceManufacturerName: String?
	/// From IOAudioDeviceModelID ("…:vendor:device").
	let audioDeviceModelID: UInt32
	var codecAddress: UInt32 = 0
	/// (vendor << 16) | device of the HDA codec.
	var codecID: UInt32 = 0
	var codecRevisionID: UInt32 = 0
	var digitalAudioCapabilities: Data?
	/// AppleALC's HDAConfigDefault entry for this codec and layout.
	var hdaConfigDefault: [String: Any]?

	var vendorName = "???"
	var deviceName = "???"
	var subVendorName = "???"
	var subDeviceName = "???"
	var codecVendorName = "???"
	var codecName = "???"
	/// From Resources/Audio/Codecs.plist: AppleALC support for this codec.
	var supportedLayoutIDs: [Int] = []
	var supportedRevisions: [String] = []
	var minKernel: Int = 0
	var maxKernel: Int = 0

	var isAppleHDA: Bool { return deviceClass == "AppleHDADriver" }
	var isVoodooHDA: Bool { return deviceClass == "VoodooHDADevice" }

	/// A device ID AppleALC needs spoofed to for this controller, from Intel/SpoofAudio.plist.
	var spoofDeviceID: UInt32? {
		return (BundledData.intelSpoofAudio[String(format: "%08X", deviceID)] as? NSNumber)?.uint32Value
	}

	static func all() -> [AudioDevice] {
		var devices: [AudioDevice] = []
		for pci in IORegistryEntry.services(matching: "IOPCIDevice") {
			// Audio devices below this controller, stopping at the next PCI device.
			for entry in pci.descendants() {
				if entry.conforms(to: "IOPCIDevice") {
					break
				}
				guard entry.conforms(to: "IOAudioDevice"), var device = AudioDevice(entry: entry, controller: pci) else { continue }
				device.addNames()
				devices.append(device)
			}
		}
		return devices
	}

	private init?(entry: IORegistryEntry, controller: IORegistryEntry) {
		let properties = entry.properties
		var modelID: UInt32 = 0
		if let model = properties["IOAudioDeviceModelID"] as? String {
			let parts = model.split(separator: ":")
			if parts.count == 3, let vendor = UInt32(parts[1], radix: 16), let product = UInt32(parts[2], radix: 16) {
				modelID = vendor << 16 | product
			}
		}
		let pci = controller.properties
		deviceClass = entry.className
		bundleID = properties["CFBundleIdentifier"] as? String
		deviceID = (IOValue.uint32(pci["vendor-id"]) ?? 0) << 16 | (IOValue.uint32(pci["device-id"]) ?? 0)
		subDeviceID = (IOValue.uint32(pci["subsystem-vendor-id"]) ?? 0) << 16 | (IOValue.uint32(pci["subsystem-id"]) ?? 0)
		revisionID = IOValue.uint32(pci["revision-id"]) ?? 0
		alcLayoutID = IOValue.uint32(pci["alc-layout-id"]) ?? 0
		audioDeviceName = properties["IOAudioDeviceName"] as? String
		audioDeviceManufacturerName = properties["IOAudioDeviceManufacturerName"] as? String
		audioDeviceModelID = modelID

		if let codec = entry.ancestor(conformingTo: ["IOHDACodecDevice"]) {
			let codecProperties = codec.properties
			digitalAudioCapabilities = codecProperties["DigitalAudioCapabilities"] as? Data
			codecAddress = IOValue.uint32(codecProperties["IOHDACodecAddress"]) ?? 0
			codecID = IOValue.uint32(codecProperties["IOHDACodecVendorID"]) ?? 0
			codecRevisionID = IOValue.uint32(codecProperties["IOHDACodecRevisionID"]) ?? 0
		}
		if let codec = entry.ancestor(conformingTo: ["AppleHDACodec"]) {
			hdaConfigDefault = (codec.property("HDAConfigDefault") as? [[String: Any]])?.first
		}
	}

	private mutating func addNames() {
		let pci = IDDatabase.pci
		vendorName = pci.vendorName(deviceID >> 16) ?? "???"
		deviceName = pci.deviceName(vendorID: deviceID >> 16, deviceID: deviceID & 0xFFFF) ?? "???"
		subVendorName = pci.vendorName(subDeviceID >> 16) ?? "???"
		subDeviceName = pci.deviceName(vendorID: subDeviceID >> 16, deviceID: subDeviceID & 0xFFFF) ?? "???"

		if let vendor = BundledData.audioVendors.first(where: { ($0.value as? NSNumber)?.uint32Value == codecID >> 16 }) {
			codecVendorName = vendor.key
		}
		if let name = AudioDevice.codecName(codecID: codecID & 0xFFFF, revisionID: codecRevisionID) {
			codecName = name
		}
		if let codec = AudioDevice.appleALCCodecs.first(where: { ($0["CodecID"] as? NSNumber)?.uint32Value == codecID }) {
			codecName = codec["CodecName"] as? String ?? codecName
			supportedLayoutIDs = (codec["LayoutIDs"] as? [NSNumber] ?? []).map { $0.intValue }
			supportedRevisions = codec["Revisions"] as? [String] ?? []
			minKernel = (codec["MinKernel"] as? NSNumber)?.intValue ?? 0
			maxKernel = (codec["MaxKernel"] as? NSNumber)?.intValue ?? 0
		}
	}

	/// Codec name from Intel/AudioCodecs.plist, preferring an exact revision match.
	private static func codecName(codecID: UInt32, revisionID: UInt32) -> String? {
		guard codecID != 0 else { return nil }
		let codecs = BundledData.audioCodecs
		func id(_ codec: [String: Any], _ key: String) -> UInt32? { return (codec[key] as? NSNumber)?.uint32Value }
		let exact = codecs.first { id($0, "DeviceID") == codecID && id($0, "RevisionID") == revisionID }
		let any = codecs.first { id($0, "DeviceID") == codecID }
		return (exact ?? any)?["Name"] as? String
	}

	/// AppleALC's codec list (Resources/Audio/Codecs.plist).
	static let appleALCCodecs: [[String: Any]] = BundledData.plist("Codecs", in: "Audio") as? [[String: Any]] ?? []

	/// Pin complexes configured by the codec's BootConfigData verbs.
	var pinNodes: [PinNode] {
		guard let verbs = hdaConfigDefault?["BootConfigData"] as? Data else { return [] }
		return PinNode.nodes(fromVerbs: verbs)
	}
}

/// One HDA pin complex's configuration default, decoded from 0x71C–0x71F verbs.
struct PinNode {
	let nid: UInt8
	var port: UInt8 = 4
	var location: UInt8 = 0
	var device: UInt8 = 0
	var connector: UInt8 = 0
	var color: UInt8 = 0
	var misc: UInt8 = 0
	var group: UInt8 = 0xF
	var index: UInt8 = 0
	var eapd: UInt8 = 0

	init(nid: UInt8) {
		self.nid = nid
	}

	/// Parses big-endian 32-bit verbs: codec address (4) | node (8) | command (12) | data (8).
	static func nodes(fromVerbs data: Data) -> [PinNode] {
		var nodes: [PinNode] = []
		for offset in stride(from: 0, to: data.count - 3, by: 4) {
			let verb = data[data.startIndex + offset..<data.startIndex + offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
			let nid = UInt8((verb >> 20) & 0xFF)
			let command = (verb >> 8) & 0xFFF
			let value = UInt8(verb & 0xFF)
			let index = nodes.firstIndex { $0.nid == nid } ?? {
				nodes.append(PinNode(nid: nid))
				return nodes.count - 1
			}()
			nodes[index].apply(command: command, data: value)
		}
		return nodes
	}

	mutating func apply(command: UInt32, data: UInt8) {
		let high = (data >> 4) & 0xF
		let low = data & 0xF
		switch command {
		case 0x70C: eapd = data
		case 0x71C: group = high; index = low
		case 0x71D: color = high; misc = low
		case 0x71E: device = high; connector = low
		case 0x71F: port = (data >> 6) & 0x3; location = data & 0x3F
		default: break
		}
	}

	var pinDefault: UInt32 {
		return UInt32(port) << 30 | UInt32(location) << 24 | UInt32(device) << 20 | UInt32(connector) << 16
			| UInt32(color) << 12 | UInt32(misc) << 8 | UInt32(group) << 4 | UInt32(index)
	}

	var grossLocation: UInt8 { return (location >> 4) & 0x3 }
	var geometricLocation: UInt8 { return location & 0xF }
	var isOutput: Bool { return device <= 0x7 }
	var isInput: Bool { return device > 0x7 && device <= 0xD }
	var hasEAPD: Bool { return eapd & 0x2 != 0 }

	// MARK: Names (HDA specification, section 7.3.3.31)

	var nodeName: String { return String(format: "%02d (0x%02X)", nid, nid) }
	var direction: String { return isOutput ? L("Out") : isInput ? L("In") : "--" }

	var deviceName: String {
		return L(["Line Out", "Speaker", "HP Out", "CD", "SPDIF Out", "Digital Other Out", "Modem Line Side", "Modem Handset Side",
		          "Line In", "AUX", "Mic In", "Telephony", "SPDIF In", "Digital Other In", "Reserved", "Other"][Int(device & 0xF)])
	}

	var connectorName: String {
		return L(["Unknown", "1/8\" Stereo/Mono", "1/4\" Stereo/Mono", "ATAPI Internal", "RCA", "Optical", "Other Digital", "Other Analog",
		          "Multichannel Analog", "XLR/Professional", "RJ-11 (Modem)", "Combination", "Unknown", "Unknown", "Unknown", "Other"][Int(connector & 0xF)])
	}

	var portName: String {
		return L(["Jack", "No Connection", "Fixed", "Jack + Internal"][Int(port & 0x3)])
	}

	var grossLocationName: String {
		return L(["External", "Internal", "Separate", "Other"][Int(grossLocation)])
	}

	var locationName: String {
		switch geometricLocation {
		case 0x7: return L(["Rear Panel", "Riser", "Special", "Mobile Lid-Inside"][Int(grossLocation)])
		case 0x8: return L(["Drive Bay", "Digital Display", "Special", "Mobile Lid-Outside"][Int(grossLocation)])
		case 0x9: return L(["Special", "ATAPI", "Special", "Special"][Int(grossLocation)])
		default:
			return L(["N/A", "Rear", "Front", "Left", "Right", "Top", "Bottom", "Special", "Special", "Special",
			          "Reserved", "Reserved", "Reserved", "Reserved", "Reserved", "Reserved"][Int(geometricLocation)])
		}
	}

	var colorName: String {
		return L(["Unknown", "Black", "Gray", "Blue", "Green", "Red", "Orange", "Yellow", "Purple", "Pink",
		          "Reserved1", "Unknown", "Unknown", "Reserved2", "White", "Other"][Int(color & 0xF)])
	}

	/// The jack colour for drawing, nil when unknown.
	var jackColor: NSColor? {
		switch color & 0xF {
		case 1: return .black
		case 2: return .systemGray
		case 3: return .systemBlue
		case 4: return .systemGreen
		case 5: return .systemRed
		case 6: return .systemOrange
		case 7: return .systemYellow
		case 8: return .systemPurple
		case 9: return .systemPink
		case 14: return .white
		default: return nil
		}
	}
}
