//
//  FramebufferTable.swift
//  Hackintool
//
//  A generation's table of framebuffer records: the original values and the user's
//  edited copy, loaded from bundled dumps, the installed kext or WhateverGreen.
//

import Foundation

final class FramebufferTable {
	enum Source: Int {
		/// The framebuffer kext installed on this Mac.
		case installedKext
		/// Tables dumped from macOS 10.13.6 / 10.14 kexts, bundled with the app.
		case macOS10_13_6
		case macOS10_14
		/// WhateverGreen's copy of the table before / after it applied patches.
		case ioregNative
		case ioregPatched
	}

	let generation: IntelGeneration
	let kind: FramebufferKind
	private(set) var original: [Framebuffer]
	var modified: [Framebuffer]

	/// Sandy Bridge records carry no ID; they're addressed by these platform IDs.
	static let sandyBridgePlatformIDs: [UInt32] = [0x0001_0000, 0x0002_0000, 0x0003_0010, 0x0003_0030, 0x0004_0000, 0xFFFF_FFFF, 0xFFFF_FFFF, 0x0003_0020, 0x0005_0000]

	private init(generation: IntelGeneration, kind: FramebufferKind, records: [Framebuffer]) {
		self.generation = generation
		self.kind = kind
		original = records
		modified = records
	}

	var platformIDs: [UInt32] {
		if kind == .sandyBridge {
			return Array(FramebufferTable.sandyBridgePlatformIDs.prefix(original.count))
		}
		return original.map { $0.framebufferID ?? 0 }
	}

	func index(of platformID: UInt32) -> Int? {
		return platformIDs.firstIndex(of: platformID)
	}

	func hasChanges(at index: Int) -> Bool {
		return original[index] != modified[index]
	}

	func reset(at index: Int) {
		modified[index] = original[index]
	}

	// MARK: Loading

	static func load(_ generation: IntelGeneration, from source: Source) -> FramebufferTable? {
		switch source {
		case .installedKext:
			guard let kext = generation.framebufferKext,
			      let data = FileManager.default.contents(atPath: "/System/Library/Extensions/\(kext).kext/Contents/MacOS/\(kext)") else {
				// Not installed (e.g. on newer macOS); fall back to the bundled table.
				return load(generation, from: .macOS10_14) ?? load(generation, from: .macOS10_13_6)
			}
			// A kext whose table can't be found (e.g. a newer layout) falls back the same way.
			return parse(data, generation: generation) ?? load(generation, from: .macOS10_14) ?? load(generation, from: .macOS10_13_6)
		case .macOS10_13_6 where generation == .iceLakeLP:
			// The 10.13.6 Ice Lake dump predates the final layout.
			return load(generation, from: .macOS10_14)
		case .macOS10_13_6, .macOS10_14:
			// The 10.14 dumps lack Sandy Bridge.
			let folder = source == .macOS10_14 && generation != .sandyBridge ? "macOS 10.14" : "macOS 10.13.6"
			guard let url = Bundle.main.url(forResource: generation.name, withExtension: "bin", subdirectory: "Framebuffer/\(folder)"),
			      let data = try? Data(contentsOf: url) else { return nil }
			return parse(data, generation: generation)
		case .ioregNative, .ioregPatched:
			let whateverGreen = IORegistryEntry(path: "IOService:/IOResources/WhateverGreen")
			guard let native = whateverGreen?.data("platform-table-native"),
			      let table = parse(native, generation: generation) else { return nil }
			if source == .ioregPatched, let patched = whateverGreen?.data("platform-table-patched") {
				let size = table.kind.layout.size
				for index in table.modified.indices where (index + 1) * size <= patched.count {
					table.modified[index].bytes = Array(patched[index * size..<(index + 1) * size])
				}
			}
			return table
		}
	}

	/// Finds the platform table in kext (or table) data: it starts with a generation's first
	/// platform ID and runs until an 0xFFFFFFFF terminator. Sandy Bridge has no terminator: it has a
	/// fixed 9 entries (WhateverGreen's SandyPlatformNum), the last being the default frame.
	static func parse(_ data: Data, generation: IntelGeneration) -> FramebufferTable? {
		let bytes = [UInt8](data)
		func word(at offset: Int) -> UInt32 {
			return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
		}
		let kinds: [FramebufferKind] = [.sandyBridge, .ivyBridge, .haswell, .broadwell, .skylake, .coffeeLake, .cannonLake, .iceLakeLP]

		var offset = 0
		while offset + 4 <= bytes.count {
			let value = word(at: offset)
			// Kaby Lake's table starts with its own ID but uses the Skylake layout.
			let kind = kinds.first { $0.firstPlatformID == value } ?? (value == 0x591E_0000 ? .skylake : nil)
			guard let found = kind else {
				offset += 4
				continue
			}
			let size = found.layout.size
			var records: [Framebuffer] = []
			while offset + size <= bytes.count {
				if found != .sandyBridge && word(at: offset) == 0xFFFF_FFFF {
					break
				}
				records.append(Framebuffer(kind: found, bytes: Array(bytes[offset..<offset + size])))
				offset += size
				if found == .sandyBridge && records.count == sandyBridgePlatformIDs.count {
					break
				}
			}
			return records.isEmpty ? nil : FramebufferTable(generation: generation, kind: found, records: records)
		}
		return nil
	}

	// MARK: Names

	/// "Intel UHD Graphics 630" for a platform ID, from the bundled GPU list.
	static func gpuName(for platformID: UInt32, generation: IntelGeneration) -> String? {
		guard let deviceID = gpuDeviceID(for: platformID, generation: generation) else { return nil }
		return BundledData.intelGPUs[String(format: "0x%04X", deviceID >> 16)] as? String
	}

	/// The GPU device ID a platform ID implies ((platform >> 16) | 0x8086), if that GPU belongs to the generation.
	static func gpuDeviceID(for platformID: UInt32, generation: IntelGeneration) -> UInt32? {
		let deviceID = (platformID & 0xFFFF_0000) | 0x8086
		let known = (BundledData.intelDeviceIDs[generation.name] as? String)?.split(separator: " ") ?? []
		return known.contains(Substring(String(format: "0x%08X", deviceID))) ? deviceID : nil
	}

	/// Mac models that use a platform ID ("MacBookPro15,1, iMac19,1").
	static func modelNames(for platformID: UInt32) -> String {
		return BundledData.intelModels[String(format: "0x%08X", platformID)] as? String ?? ""
	}

	/// The GPU device IDs supported by a generation's framebuffer, for device-id spoofing.
	static func deviceIDs(for generation: IntelGeneration) -> [UInt32] {
		let list = (BundledData.intelDeviceIDs[generation.name] as? String)?.split(separator: " ") ?? []
		return list.compactMap { String($0).hexOrDecimalValue.map { UInt32(truncatingIfNeeded: $0) >> 16 } }
	}

	/// The generation a platform ID belongs to, from the bundled PlatformIDs lists.
	static func generation(of platformID: UInt32) -> IntelGeneration? {
		for folder in ["macOS 10.14", "macOS 10.13.6"] {
			guard let lists = BundledData.plist("PlatformIDs", in: "Framebuffer/\(folder)") as? [String: String] else { continue }
			for generation in IntelGeneration.allCases {
				let ids = lists[generation.name]?.split(separator: " ").compactMap { String($0).hexOrDecimalValue } ?? []
				if ids.contains(UInt64(platformID)) {
					return generation
				}
			}
		}
		return nil
	}
}
