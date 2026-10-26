//
//  RadeonGPU.swift
//  Hackintool
//
//  AMD Radeon GPUs: which family a card is (from its pci.ids codename), whether macOS
//  has a driver for it, and the WhateverGreen device properties and boot-args to set.
//  Every property and boot-arg here is one WhateverGreen documents (README and
//  Manual/FAQ.Radeon.en.md). Named framebuffers (Baladi, Futomaki...) are left out on
//  purpose: WhateverGreen says they should never be used.
//

import Foundation

enum RadeonFamily {
	case teraScale, gcn1, gcn2, gcn3, polaris, polaris22, lexa, vega, navi1x, navi21, navi23
	case unsupportedDiscrete
	/// Vega-based Ryzen APU graphics, which NootedRed drives.
	case vegaAPU
	/// Other APU graphics (RDNA Ryzen, pre-Ryzen A-series), which nothing drives.
	case unsupportedAPU
	case unknown

	var name: String {
		switch self {
		case .teraScale: return "TeraScale (HD 5000/6000)"
		case .gcn1: return "GCN 1 (HD 7000)"
		case .gcn2: return "GCN 2 (R7/R9 200/300)"
		case .gcn3: return "GCN 3 (R9 285/380/Fury)"
		case .polaris: return "Polaris (RX 400/500)"
		case .polaris22: return "Polaris 22 (RX Vega M)"
		case .lexa: return "Lexa / Polaris 12"
		case .vega: return "Vega"
		case .navi1x: return "Navi 1x (RX 5000)"
		case .navi21: return "Navi 21 (RX 6800/6900)"
		case .navi23: return "Navi 23 (RX 6600)"
		case .unsupportedDiscrete: return L("Unsupported Radeon")
		case .vegaAPU: return "Ryzen APU (Vega)"
		case .unsupportedAPU: return L("AMD APU (no macOS driver)")
		case .unknown: return L("Unknown")
		}
	}

	/// The macOS versions with a driver for the family, or nil when there's none.
	var macOSRange: (first: String, last: String)? {
		switch self {
		case .teraScale: return ("10.6", "10.13")
		case .gcn1, .gcn2, .gcn3: return ("10.8", "12")
		case .polaris: return ("10.12", "26")
		case .polaris22: return ("10.14", "26")
		case .vega: return ("10.13", "26")
		case .navi1x: return ("10.15", "26")
		case .navi21: return ("11", "26")
		case .navi23: return ("12", "26")
		case .vegaAPU, .lexa, .unsupportedDiscrete, .unsupportedAPU, .unknown: return nil
		}
	}

	var isAPU: Bool { return self == .vegaAPU || self == .unsupportedAPU }
	var isNavi: Bool { return self == .navi1x || self == .navi21 || self == .navi23 }

	var support: String {
		switch self {
		case .vegaAPU: return L("No Apple driver; NootedRed adds support")
		case .lexa: return L("No Apple driver (some cards work with a device-id spoof)")
		case .unsupportedDiscrete, .unsupportedAPU: return L("No macOS driver")
		case .unknown: return L("Unknown")
		default:
			guard let range = macOSRange else { return "" }
			return L("macOS %@ – %@", range.first, range.last)
		}
	}

	/// Codenames as pci.ids starts the device names ("Navi 21 [Radeon RX 6800...]").
	private static let codenames: [(String, RadeonFamily)] = [
		("Cedar", .teraScale), ("Redwood", .teraScale), ("Juniper", .teraScale), ("Cypress", .teraScale), ("Hemlock", .teraScale),
		("Caicos", .teraScale), ("Turks", .teraScale), ("Barts", .teraScale), ("Cayman", .teraScale), ("Antilles", .teraScale),
		("Seymour", .teraScale), ("Whistler", .teraScale), ("Thames", .teraScale), ("Blackcomb", .teraScale), ("Madison", .teraScale), ("Park", .teraScale),
		("Onega", .teraScale), ("Lexington", .teraScale), ("Broadway", .teraScale), ("Granville", .teraScale), ("Pinewood", .teraScale), ("Robson", .teraScale),
		("Tahiti", .gcn1), ("Pitcairn", .gcn1), ("Curacao", .gcn1), ("Trinidad", .gcn1), ("Cape Verde", .gcn1), ("Heathrow", .gcn1), ("Chelsea", .gcn1), ("Wimbledon", .gcn1),
		("Oland", .unsupportedDiscrete), ("Hainan", .unsupportedDiscrete), ("Mars", .unsupportedDiscrete), ("Sun", .unsupportedDiscrete),
		("Bonaire", .gcn2), ("Hawaii", .gcn2), ("Vesuvius", .gcn2), ("Grenada", .gcn2), ("Saturn", .gcn2), ("Neptune", .gcn2), ("Strato", .gcn2), ("Emerald", .gcn2), ("Tobago", .gcn2),
		("Tonga", .gcn3), ("Antigua", .gcn3), ("Amethyst", .gcn3), ("Fiji", .gcn3),
		("Topaz", .unsupportedDiscrete), ("Iceland", .unsupportedDiscrete), ("Meso", .unsupportedDiscrete), ("Weston", .unsupportedDiscrete),
		("Ellesmere", .polaris), ("Baffin", .polaris), ("Polaris 20", .polaris), ("Polaris 21", .polaris), ("Polaris 23", .lexa),
		("Polaris 22", .polaris22), ("Lexa", .lexa), ("Polaris 12", .lexa),
		("Vega 10", .vega), ("Vega 12", .vega), ("Vega 20", .vega),
		("Navi 10", .navi1x), ("Navi 12", .navi1x), ("Navi 14", .navi1x), ("Navi 21", .navi21), ("Navi 23", .navi23),
		("Navi 22", .unsupportedDiscrete), ("Navi 24", .unsupportedDiscrete), ("Navi 31", .unsupportedDiscrete), ("Navi 32", .unsupportedDiscrete),
		("Navi 33", .unsupportedDiscrete), ("Navi 44", .unsupportedDiscrete), ("Navi 48", .unsupportedDiscrete),
		("Raven Ridge", .vegaAPU), ("Raven", .vegaAPU), ("Picasso", .vegaAPU), ("Renoir", .vegaAPU), ("Lucienne", .vegaAPU),
		("Cezanne", .vegaAPU), ("Barcelo", .vegaAPU), ("Dali", .vegaAPU), ("Pollock", .vegaAPU),
		("Rembrandt", .unsupportedAPU), ("Raphael", .unsupportedAPU), ("Phoenix", .unsupportedAPU), ("Mendocino", .unsupportedAPU),
		("Hawk Point", .unsupportedAPU), ("HawkPoint", .unsupportedAPU), ("Strix", .unsupportedAPU), ("Krackan", .unsupportedAPU),
		("Van Gogh", .unsupportedAPU), ("VanGogh", .unsupportedAPU), ("Granite Ridge", .unsupportedAPU),
		// Pre-Ryzen A-series and console APUs
		("Kaveri", .unsupportedAPU), ("Kabini", .unsupportedAPU), ("Mullins", .unsupportedAPU), ("Beema", .unsupportedAPU),
		("Carrizo", .unsupportedAPU), ("Stoney", .unsupportedAPU), ("Bristol Ridge", .unsupportedAPU), ("Godavari", .unsupportedAPU),
		("Trinity", .unsupportedAPU), ("Richland", .unsupportedAPU), ("Wrestler", .unsupportedAPU), ("Temash", .unsupportedAPU),
		("Kalindi", .unsupportedAPU), ("Sumo", .unsupportedAPU), ("SuperSumo", .unsupportedAPU), ("Kryptos", .unsupportedAPU),
	]

	/// The family for a pci.ids device name. A codename ending in a number must not be followed
	/// by another digit ("Navi 2" isn't "Navi 21"); others may be ("Phoenix1", "HawkPoint2").
	static func family(forDeviceName name: String) -> RadeonFamily {
		for (codename, family) in codenames.sorted(by: { $0.0.count > $1.0.count }) where name.hasPrefix(codename) {
			let rest = name.dropFirst(codename.count)
			if codename.last?.isNumber == true, let next = rest.first, next.isNumber {
				continue
			}
			return family
		}
		return .unknown
	}
}

/// A Radeon to configure: one found in this machine, or one entered by hand.
struct RadeonGPU {
	let deviceID: UInt32
	let name: String
	/// e.g. "PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)".
	var devicePath: String
	let isDetected: Bool

	var family: RadeonFamily { return RadeonFamily.family(forDeviceName: name) }

	var title: String {
		return String(format: "%@ (0x%04X)", name, deviceID)
	}

	/// AMD display controllers in the I/O Registry.
	static func detected() -> [RadeonGPU] {
		return PCIDevice.all()
			.filter { $0.vendorID == PCIVendor.amd && $0.classCode >> 16 == 0x03 }
			.map { RadeonGPU(deviceID: $0.deviceID, name: $0.deviceName, devicePath: $0.devicePath, isDetected: true) }
	}

	/// A card that isn't in this machine, named from pci.ids.
	static func manual(deviceID: UInt32, devicePath: String) -> RadeonGPU {
		let database = IDDatabase.pci
		database.loadIfNeeded()
		let name = database.deviceName(vendorID: PCIVendor.amd, deviceID: deviceID) ?? L("Unknown")
		return RadeonGPU(deviceID: deviceID, name: name, devicePath: devicePath, isDetected: false)
	}

	/// What's worth knowing before setting anything.
	var notes: [String] {
		var notes: [String] = []
		switch family {
		case .vegaAPU:
			notes.append(L("Ryzen APU graphics have no Apple driver. NootedRed (ChefKiss) adds support for Vega-based APUs: install it from Extensions and follow its own setup guide."))
		case .unsupportedAPU:
			notes.append(L("No macOS driver exists for this APU's graphics. Use a supported discrete GPU; Disable GPU keeps macOS from trying to use it."))
		case .unsupportedDiscrete:
			notes.append(L("macOS has no driver for this GPU. Disable GPU lets macOS boot on another GPU."))
		case .lexa:
			notes.append(L("Lexa cards have no Apple driver. Some RX 550/540 cards work with a device-id spoof to a supported Polaris card; otherwise disable it."))
		case .polaris22:
			notes.append(L("RX Vega M needs the Polaris22Fixup kext (in Extensions)."))
		case .gcn1, .gcn2, .gcn3:
			notes.append(L("Apple dropped GCN 1–3 drivers after macOS 12 Monterey."))
		case .teraScale:
			notes.append(L("TeraScale cards have no Metal driver, so macOS 10.14 and later can't use them."))
		case .navi1x, .navi21, .navi23:
			notes.append(L("Navi cards need agdpmod=pikera with the iMacPro1,1 and MacPro7,1 SMBIOS, or the screen goes black at boot."))
		default:
			break
		}
		if name.contains("Cape Verde") {
			notes.append(L("Cape Verde (HD 7730/7750/7770, R7 250/250X) needs radpg=15 to initialise."))
		}
		if name.hasPrefix("Hawaii") || name.contains("R7 370") || name.contains("R9 370") {
			notes.append(L("290X and 370 cards need DVI transmitter correction (-raddvi) for some connectors."))
		}
		if family.macOSRange != nil {
			notes.append(L("Most supported cards need nothing beyond Lilu and WhateverGreen; only set what fixes a problem you have."))
		}
		return notes
	}
}

/// The WhateverGreen settings for one Radeon.
struct RadeonOptions {
	// Device properties
	var agdpmodPikera = false
	var disableGPU = false
	var spoofDeviceID: UInt32?
	var model = ""
	var slotName = ""
	/// shikigva: 0 (off), 16 or 80 (AMD DRM for Music, Safari and TV).
	var shikigva = 0
	var unfairgva = false
	var enableGvaSupport = false
	var forceSMUFirmware = false
	var disableAGDC = false
	// Boot-args (WhateverGreen has no property equivalent)
	var radDVI = false
	var radPG15 = false
	var rad24 = false
	var radCodec = false
	var radVESA = false
	var applbkl3 = false

	/// Sensible defaults for a family.
	init(for gpu: RadeonGPU) {
		switch gpu.family {
		case .navi1x, .navi21, .navi23:
			agdpmodPikera = true
		case .unsupportedDiscrete, .unsupportedAPU, .lexa:
			disableGPU = true
		default:
			break
		}
		radPG15 = gpu.name.contains("Cape Verde")
	}

	/// The device properties for the GPU, in OpenCore DeviceProperties types.
	func properties() -> [String: Any] {
		var properties: [String: Any] = [:]
		if disableGPU {
			// Nothing else matters for a GPU macOS won't use.
			properties["disable-gpu"] = RadeonOptions.uint32(1)
			return properties
		}
		if agdpmodPikera {
			// WhateverGreen requires the data to be null terminated.
			properties["agdpmod"] = Data("pikera".utf8) + Data([0])
		}
		if let spoof = spoofDeviceID {
			properties["device-id"] = RadeonOptions.uint32(spoof & 0xFFFF)
		}
		let model = self.model.trimmingCharacters(in: .whitespaces)
		if !model.isEmpty {
			properties["model"] = model
		}
		let slot = slotName.trimmingCharacters(in: .whitespaces)
		if !slot.isEmpty {
			properties["AAPL,slot-name"] = slot
		}
		if shikigva != 0 {
			properties["shikigva"] = RadeonOptions.uint32(UInt32(shikigva))
		}
		if unfairgva {
			properties["unfairgva"] = RadeonOptions.uint32(1)
		}
		if enableGvaSupport {
			properties["enable-gva-support"] = RadeonOptions.uint32(1)
		}
		if forceSMUFirmware {
			// WhateverGreen turns a single 01 byte into a boolean.
			properties["Force_Load_FalconSMUFW"] = Data([1])
		}
		if disableAGDC {
			properties["CFG,CFG_USE_AGDC"] = Data([0])
		}
		return properties
	}

	var bootArgs: [String] {
		var args: [String] = []
		if radDVI { args.append("-raddvi") }
		if radPG15 { args.append("radpg=15") }
		if rad24 { args.append("-rad24") }
		if radCodec { args.append("-radcodec") }
		if radVESA { args.append("-radvesa") }
		if applbkl3 { args.append("applbkl=3") }
		return args
	}

	static func uint32(_ value: UInt32) -> Data {
		var little = value.littleEndian
		return Data(bytes: &little, count: 4)
	}
}

enum RadeonConfig {
	/// The properties and boot-args as they'd appear in config.plist.
	static func preview(path: String, options: RadeonOptions, format: BootloaderConfigFormat) -> String {
		let config = ConfigPlist(format: format)
		apply(path: path, options: options, to: config)
		return config.xmlString
	}

	/// Merges the properties into the GPU's DeviceProperties entry and adds the boot-args.
	static func apply(path: String, options: RadeonOptions, to config: ConfigPlist) {
		let properties = options.properties()
		if !properties.isEmpty {
			let devices = config.deviceProperties
			let entry = (devices[path] as? NSMutableDictionary) ?? NSMutableDictionary()
			properties.forEach { entry[$0.key] = $0.value }
			devices[path] = entry
		}
		config.addBootArgs(options.bootArgs)
	}
}
