//
//  DisplayOverride.swift
//  Hackintool
//
//  Patched EDIDs, HiDPI scaled resolutions and display override files.
//  Based on FixEDID by Andy Vandijck.
//

import Foundation

/// A 128-byte EDID base block, edited in place by byte offset.
/// See https://elixir.bootlin.com/linux/latest/source/include/drm/drm_edid.h
struct EDID {
	var bytes: [UInt8]

	init?(_ data: Data) {
		guard data.count >= 128 else { return nil }
		bytes = Array(data)
	}

	init(template: [UInt8]) {
		bytes = template
	}

	var data: Data { return Data(bytes) }

	// Offsets into the base block.
	static let vendorOffset = 8
	static let productOffset = 10
	static let versionOffset = 18
	static let basicParamsOffset = 20
	static let chromaOffset = 25
	static let detailedTimingsOffset = 54
	static let checksumOffset = 127

	/// Manufacturer ID, stored big-endian.
	var vendorID: UInt16 {
		get { return UInt16(bytes[8]) << 8 | UInt16(bytes[9]) }
		set { bytes[8] = UInt8(newValue >> 8); bytes[9] = UInt8(newValue & 0xFF) }
	}

	/// Product code, stored little-endian.
	var productID: UInt16 {
		get { return UInt16(bytes[11]) << 8 | UInt16(bytes[10]) }
		set { bytes[10] = UInt8(newValue & 0xFF); bytes[11] = UInt8(newValue >> 8) }
	}

	mutating func replace(at offset: Int, with values: [UInt8]) {
		bytes.replaceSubrange(offset..<offset + values.count, with: values)
	}

	mutating func updateChecksum() {
		let sum = bytes[0..<127].reduce(UInt8(0)) { $0 &+ $1 }
		bytes[EDID.checksumOffset] = 0 &- sum
	}

	// MARK: Detailed timing descriptors (four 18-byte blocks)

	private func descriptor(_ index: Int) -> ArraySlice<UInt8> {
		let start = EDID.detailedTimingsOffset + index * 18
		return bytes[start..<start + 18]
	}

	/// A display descriptor (not a pixel timing) of the given tag: FC name, FD range, FF serial...
	private func descriptorTag(_ index: Int) -> UInt8? {
		let block = descriptor(index)
		let start = block.startIndex
		guard block[start] == 0, block[start + 1] == 0, block[start + 2] == 0 else { return nil }
		return block[start + 3]
	}

	private func isReplaceable(_ index: Int) -> Bool {
		// Undefined, manufacturer-specific and dummy descriptors can be reused; name,
		// range and serial descriptors are kept.
		guard let tag = descriptorTag(index) else { return false }
		return tag <= 0x10 || (0xF7...0xFB).contains(tag) || tag == 0xFE
	}

	/// Puts an 18-byte descriptor in the slot holding `tag`, else in a reusable slot,
	/// else in the last slot that isn't a name, serial or range descriptor.
	mutating func setDescriptor(_ values: [UInt8], replacing tag: UInt8) {
		let protected: Set<UInt8> = [0xFC, 0xFD, 0xFF]
		let slot = (0..<4).first { descriptorTag($0) == tag }
			?? (0..<4).first { isReplaceable($0) }
			?? (0..<4).reversed().first { descriptorTag($0).map { !protected.contains($0) } ?? true }
		guard let index = slot else { return }
		replace(at: EDID.detailedTimingsOffset + index * 18, with: values)
	}

	/// Native resolution from the first pixel timing descriptor.
	var nativeResolution: (width: Int, height: Int)? {
		for index in 0..<4 where descriptorTag(index) == nil {
			let block = Array(descriptor(index))
			let width = Int(block[2]) | Int(block[4] & 0xF0) << 4
			let height = Int(block[5]) | Int(block[7] & 0xF0) << 4
			if width > 0 && height > 0 {
				return (width, height)
			}
		}
		return nil
	}

	var aspectRatio: String {
		guard let (width, height) = nativeResolution else { return "Ratio N/A" }
		func gcd(_ a: Int, _ b: Int) -> Int { return b == 0 ? a : gcd(b, a % b) }
		let divisor = gcd(width, height)
		return "\(width / divisor):\(height / divisor)"
	}
}

/// HiDPI scaling modes for display override "scale-resolutions".
enum HiDPIMode: Int, CaseIterable {
	case hiDPI1, hiDPI2, hiDPI3, hiDPI4, nonScaled, auto

	var title: String {
		return ["HiDPI 1", "HiDPI 2", "HiDPI 3", "HiDPI 4", "Non Scaled", "Auto"][rawValue]
	}

	/// What each mode writes to scale-resolutions (shown as a tooltip). The flag variants are
	/// what different macOS versions and displays accept; if a HiDPI size doesn't appear in
	/// Displays settings, try another variant.
	var detail: String {
		switch self {
		case .hiDPI1: return L("HiDPI at double this size, with a single 0 flag byte (9 bytes).")
		case .hiDPI2: return L("HiDPI at double this size, with flags 0x1 and 0x200000 (16 bytes).")
		case .hiDPI3: return L("HiDPI at double this size, with flag 0x1 (12 bytes).")
		case .hiDPI4: return L("HiDPI at double this size, with flags 0x9 and 0xA00000 (16 bytes).")
		case .nonScaled: return L("Adds this size as a normal (non-HiDPI) resolution (8 bytes).")
		case .auto: return L("Writes both HiDPI 3 and HiDPI 2 entries for this size.")
		}
	}
}

struct ScaledResolution {
	var width: Int
	var height: Int
	var mode: HiDPIMode

	/// The override's data for this mode: doubled big-endian width/height plus flags.
	///   NonScaled <wwwwwwww hhhhhhhh>, HiDPI1 <... 00>, HiDPI3 <... 00000001>,
	///   HiDPI2 <... 00000001 00200000>, HiDPI4 <... 00000009 00a00000>.
	func data(as mode: HiDPIMode) -> Data? {
		let scale = mode == .nonScaled ? 1 : 2
		var bytes: [UInt8] = []
		for value in [UInt32(width * scale), UInt32(height * scale)] {
			bytes += [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
		}
		let isHiDPI4 = mode == .hiDPI4
		bytes += [0, 0, 0, isHiDPI4 ? 0x09 : 0x01, 0, isHiDPI4 ? 0xA0 : 0x20, 0, 0]
		switch mode {
		case .hiDPI1: return Data(bytes.prefix(9))
		case .hiDPI2, .hiDPI4: return Data(bytes)
		case .hiDPI3: return Data(bytes.prefix(12))
		case .nonScaled: return Data(bytes.prefix(8))
		case .auto: return nil
		}
	}

	/// "Auto" expands to HiDPI 3 and HiDPI 2 entries.
	var overrideData: [Data] {
		if mode == .auto {
			return [data(as: .hiDPI3), data(as: .hiDPI2)].compactMap { $0 }
		}
		return data(as: mode).map { [$0] } ?? []
	}

	/// Starting resolution lists for common panel sizes.
	static func preset(_ preset: ResolutionPreset) -> [ScaledResolution] {
		func list(_ entries: [(Int, Int, HiDPIMode)]) -> [ScaledResolution] {
			return entries.map { ScaledResolution(width: $0.0, height: $0.1, mode: $0.2) }
		}
		let general = list([(1280, 720, .hiDPI2), (960, 540, .hiDPI2), (640, 360, .hiDPI2),
		                    (840, 472, .hiDPI3), (720, 405, .hiDPI3), (640, 360, .hiDPI3), (576, 324, .hiDPI3), (512, 288, .hiDPI3),
		                    (420, 234, .hiDPI3), (400, 225, .hiDPI3), (320, 180, .hiDPI3),
		                    (1920, 1080, .hiDPI4), (1680, 945, .hiDPI4), (1440, 810, .hiDPI4), (1280, 720, .hiDPI4),
		                    (1024, 576, .hiDPI4), (960, 540, .hiDPI4), (640, 360, .hiDPI4)])
		let general1200p = list([(1280, 800, .hiDPI2), (960, 600, .hiDPI2), (640, 400, .hiDPI2),
		                         (840, 525, .hiDPI3), (720, 450, .hiDPI3), (640, 400, .hiDPI3), (576, 360, .hiDPI3), (512, 320, .hiDPI3),
		                         (420, 262, .hiDPI3), (400, 250, .hiDPI3), (320, 200, .hiDPI3),
		                         (1920, 1200, .hiDPI4), (1680, 1050, .hiDPI4), (1440, 900, .hiDPI4), (1280, 800, .hiDPI4),
		                         (1024, 600, .hiDPI4), (960, 600, .hiDPI4), (640, 400, .hiDPI4)])
		switch preset {
		case .p1080:
			return list([(1920, 1080, .hiDPI1), (1680, 945, .hiDPI1), (1440, 810, .hiDPI1), (1280, 720, .hiDPI1), (1024, 576, .hiDPI1)]) + general
		case .k2:
			return list([(2048, 1152, .hiDPI1), (1920, 1080, .hiDPI1), (1680, 945, .hiDPI1), (1440, 810, .hiDPI1), (1280, 720, .hiDPI1),
			             (1024, 576, .hiDPI2), (960, 540, .hiDPI3), (2048, 1152, .hiDPI4)]) + general
		case .k4:
			return list([(4096, 2160, .hiDPI1), (3840, 2160, .hiDPI1), (3200, 1800, .hiDPI1), (3008, 1692, .hiDPI1), (2560, 1440, .hiDPI1),
			             (1920, 1080, .hiDPI2), (1600, 900, .hiDPI3), (3840, 2160, .hiDPI4)]) + general
		case .p1200:
			return list([(1920, 1200, .hiDPI1), (1680, 1050, .hiDPI1), (1440, 900, .hiDPI1), (1280, 800, .hiDPI1), (1024, 640, .hiDPI1)]) + general1200p
		case .k5:
			return list([(5120, 2880, .hiDPI1), (3840, 2160, .hiDPI1), (3360, 1890, .hiDPI1), (3200, 1800, .hiDPI1), (3008, 1692, .hiDPI1),
			             (2880, 1620, .hiDPI1), (2560, 1440, .hiDPI2), (2304, 1296, .hiDPI3), (2048, 1152, .hiDPI3),
			             (1920, 1080, .hiDPI3), (1680, 945, .hiDPI3), (5120, 2880, .hiDPI4)]) + general
		case .manual:
			return []
		}
	}
}

enum ResolutionPreset: Int, CaseIterable {
	case p1080, k2, k4, p1200, k5, manual

	var title: String {
		return ["1080p", "2K", "4K", "1200p", "5K", "Manual"][rawValue]
	}
}

/// Apple displays whose identity can be given to a third-party display.
enum EDIDProfile: Int, CaseIterable {
	case original, iMac, iMacRetina, macBookPro, macBookAir, cinemaHD, thunderbolt, ledCinema

	var title: String {
		switch self {
		case .original: return L("Display")
		case .iMac: return "Apple iMac Display (16:10)"
		case .iMacRetina: return "Apple iMac Retina Display (16:9)"
		case .macBookPro: return "Apple MacBook Pro Display (16:10)"
		case .macBookAir: return "Apple MacBook Air Display (16:9)"
		case .cinemaHD: return "Apple Cinema HD Display (16:10)"
		case .thunderbolt: return "Apple Thunderbolt Display (16:9)"
		case .ledCinema: return "Apple LED Cinema Display (16:10)"
		}
	}

	var apple: AppleDisplayData? {
		switch self {
		case .original: return nil
		case .iMac: return AppleDisplayData.iMac
		case .iMacRetina: return AppleDisplayData.iMacRetina
		case .macBookPro: return AppleDisplayData.macBookPro
		case .macBookAir: return AppleDisplayData.macBookAir
		case .cinemaHD: return AppleDisplayData.cinemaHD
		case .thunderbolt: return AppleDisplayData.thunderbolt
		case .ledCinema: return AppleDisplayData.ledCinema
		}
	}
}

/// What the user chose for one display in the Displays section.
struct DisplaySettings {
	var name: String
	var vendorIDOverride: UInt32
	var productIDOverride: UInt32
	var isInternal: Bool
	var profile: EDIDProfile = .original
	var iconIndex = 0
	var resolutionPreset: ResolutionPreset = .p1080
	var fixMonitorRanges = false
	var injectAppleVendorID = false
	var injectAppleProductID = false
	var forceRGBMode = false
	var patchColorProfile = false
	var ignoreDisplayPrefs = false
	var resolutions: [ScaledResolution] = []

	init(display: Display) {
		name = display.name
		vendorIDOverride = display.vendorID
		productIDOverride = display.productID
		isInternal = display.isInternal
	}
}

enum DisplayOverride {
	/// The EDID to start from: the display's own, or the chosen Apple display's.
	static func originalEDID(for display: Display, settings: DisplaySettings) -> EDID? {
		if let edid = display.edid.flatMap(EDID.init) {
			return edid
		}
		let template = settings.profile.apple?.edid ?? AppleDisplayData.iMacRetina.edid
		var edid = EDID(template: template)
		edid.vendorID = UInt16(truncatingIfNeeded: display.vendorID)
		edid.productID = UInt16(truncatingIfNeeded: display.productID)
		return edid
	}

	/// The EDID with the chosen fixes applied.
	static func patchedEDID(for display: Display, settings: DisplaySettings) -> EDID? {
		guard var edid = originalEDID(for: display, settings: settings) else { return nil }
		if let apple = settings.profile.apple {
			edid.replace(at: EDID.vendorOffset, with: apple.serial)
			edid.replace(at: EDID.chromaOffset, with: apple.chroma)
			edid.replace(at: EDID.basicParamsOffset, with: apple.basicParams)
			edid.replace(at: EDID.versionOffset, with: [0x01, 0x04])
			edid.setDescriptor(apple.nameDescriptor, replacing: 0xFC)
			if let serial = apple.serialDescriptor {
				edid.setDescriptor(serial, replacing: 0xFF)
			}
		} else {
			if settings.vendorIDOverride != display.vendorID {
				edid.vendorID = UInt16(truncatingIfNeeded: settings.vendorIDOverride)
			}
			if settings.productIDOverride != display.productID {
				edid.productID = UInt16(truncatingIfNeeded: settings.productIDOverride)
			}
			if settings.injectAppleVendorID {
				edid.vendorID = 0x0610
			}
			if settings.injectAppleProductID {
				edid.productID = 0x9C7C
			}
			if settings.forceRGBMode {
				// Feature support byte: colour encoding RGB 4:4:4 only.
				edid.bytes[EDID.basicParamsOffset + 4] &= ~0b11000
			}
			if settings.patchColorProfile {
				edid.replace(at: EDID.chromaOffset, with: AppleDisplayData.iMac.chroma)
			}
		}
		if settings.fixMonitorRanges {
			edid.setDescriptor(AppleDisplayData.monitorRanges, replacing: 0xFD)
		}
		edid.updateChecksum()
		return edid
	}

	/// Writes the display override, a codeless injector kext and the EDID binaries into `folder`.
	static func export(display: Display, settings: DisplaySettings, to folder: URL) throws -> [URL] {
		guard let original = originalEDID(for: display, settings: settings),
		      let patched = patchedEDID(for: display, settings: settings) else {
			throw NSError(domain: "Hackintool", code: 1, userInfo: [NSLocalizedDescriptionKey: L("No EDID is available for this display.")])
		}
		let resolutions = settings.resolutions.flatMap { $0.overrideData }
		let displayClass = settings.isInternal ? "AppleBacklightDisplay" : "AppleDisplay"
		let vendorHex = String(display.vendorID, radix: 16)
		let productHex = String(display.productID, radix: 16)

		var merge: [String: Any] = ["DisplayProductName": settings.name, "IODisplayEDID": patched.data]
		var vendorID = settings.vendorIDOverride
		var productID = settings.productIDOverride
		if let apple = settings.profile.apple {
			merge = apple.mergeProperties(name: settings.name, edid: patched.data, displayClass: displayClass, prefsKey: display.prefsKey)
			vendorID = apple.vendorID
			productID = apple.productID
		} else {
			if display.productID != productID {
				merge["DisplayProductID"] = productID
			}
			if display.vendorID != vendorID {
				merge["DisplayVendorID"] = vendorID
			}
		}
		if !resolutions.isEmpty {
			merge["scale-resolutions"] = resolutions
		}

		var override: [String: Any] = [
			"DisplayProductName": settings.name,
			"DisplayProductID": productID,
			"DisplayVendorID": vendorID,
			"IODisplayEDID": patched.data,
		]
		if !resolutions.isEmpty {
			override["scale-resolutions"] = resolutions
		}

		let fileManager = FileManager.default
		var written: [URL] = []

		// /Library/Displays/Contents/Resources/Overrides/DisplayVendorID-xxx/DisplayProductID-yyy
		let overrideFolder = folder.appendingPathComponent("DisplayVendorID-\(vendorHex)")
		try fileManager.createDirectory(at: overrideFolder, withIntermediateDirectories: true)
		let overrideFile = overrideFolder.appendingPathComponent("DisplayProductID-\(productHex)")
		try PropertyListSerialization.data(fromPropertyList: override, format: .xml, options: 0).write(to: overrideFile)
		written.append(overrideFolder)

		let originalBin = folder.appendingPathComponent("EDID-\(vendorHex)-\(productHex)-orig.bin")
		let patchedBin = folder.appendingPathComponent("EDID-\(vendorHex)-\(productHex).bin")
		try original.data.write(to: originalBin)
		try patched.data.write(to: patchedBin)
		written += [originalBin, patchedBin]

		// A codeless kext that merges the properties into the display's IODisplay service.
		let kext = folder.appendingPathComponent("Display-\(vendorHex)-\(productHex).kext")
		try? fileManager.removeItem(at: kext)
		let contents = kext.appendingPathComponent("Contents")
		try fileManager.createDirectory(at: contents, withIntermediateDirectories: true)
		let personality: [String: Any] = [
			"CFBundleIdentifier": "com.apple.driver.AppleUSBMergeNub",
			"IOClass": "AppleUSBMergeNub",
			"IOProviderClass": displayClass,
			"IOProbeScore": 5000,
			"DisplayProductID": display.productID,
			"DisplayVendorID": display.vendorID,
			"IOProviderMergeProperties": merge.filter { $0.key != "IOClass" },
		]
		let info: [String: Any] = [
			"CFBundleDevelopmentRegion": "English",
			"CFBundleIdentifier": "com.AnV.Software.driver.AppleMonitor",
			"CFBundleInfoDictionaryVersion": "6.0",
			"CFBundleName": "Display Injector",
			"CFBundlePackageType": "KEXT",
			"CFBundleSignature": "????",
			"CFBundleVersion": "9.9.9",
			"CFBundleGetInfoString": "Copyright (C) 2013 AnV Software",
			"IOKitPersonalities": ["Monitor Apple ID Injection": personality],
			"OSBundleRequired": "Root",
		]
		try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
		written.append(kext)
		return written
	}

	/// Writes Icons.plist mapping each display to a Mac icon in System Settings.
	static func exportIcons(_ displays: [(Display, DisplaySettings)], to folder: URL) -> URL? {
		let paths = ["/System/Library/Displays/Contents/Resources/Overrides/Icons.plist", "/Library/Displays/Contents/Resources/Overrides/Icons.plist"]
		guard let source = paths.lazy.compactMap({ NSDictionary(contentsOfFile: $0) }).first,
		      let icons = ConfigPlist.deepMutableCopy(source) as NSMutableDictionary?,
		      let vendors = icons["vendors"] as? NSMutableDictionary else { return nil }

		let overrides = "/System/Library/Displays/Contents/Resources/Overrides/"
		for (display, settings) in displays {
			let vendorKey = String(display.vendorID, radix: 16)
			let icon: (preview: String, icon: String, x: Int, y: Int, width: Int, height: Int)
			switch settings.iconIndex {
			case 1: icon = (overrides + "DisplayVendorID-610/DisplayProductID-a032.tiff", "com.apple.cinema-display", 33, 68, 160, 90)
			case 2: icon = (overrides + "DisplayVendorID-610/DisplayProductID-a030-e1e1df.tiff", "com.apple.cinema-display", 52, 66, 122, 76)
			case 3: icon = (overrides + "DisplayVendorID-610/DisplayProductID-a028-9d9da0.tiff", "com.apple.cinema-display", 40, 62, 147, 92)
			case 4: icon = (overrides + "DisplayVendorID-1e6d/DisplayProductID-5b11.tiff", overrides + "DisplayVendorID-1e6d/DisplayProductID-5b11.icns", 11, 47, 202, 114)
			default:
				vendors.removeObject(forKey: vendorKey)
				continue
			}
			vendors[vendorKey] = [String(display.productID, radix: 16): [
				"display-resolution-preview-icon": icon.preview,
				"resolution-preview-x": icon.x,
				"resolution-preview-y": icon.y,
				"resolution-preview-width": icon.width,
				"resolution-preview-height": icon.height,
				"display-icon": icon.icon,
			]]
		}
		let destination = folder.appendingPathComponent("Icons.plist")
		return icons.write(to: destination, atomically: true) ? destination : nil
	}
}
