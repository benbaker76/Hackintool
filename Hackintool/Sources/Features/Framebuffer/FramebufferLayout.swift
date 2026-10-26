//
//  FramebufferLayout.swift
//  Hackintool
//
//  Byte layouts of Intel framebuffer platform tables, per generation.
//  Offsets match vit9696's IntelFramebuffer definitions (packed, little-endian),
//  as computed by the compiler from the original C++ structs.
//

import Foundation

/// The binary record layouts. Kaby Lake shares Skylake's.
enum FramebufferKind {
	case sandyBridge, ivyBridge, haswell, broadwell, skylake, coffeeLake, cannonLake, iceLakeLP, iceLakeHP

	init(_ generation: IntelGeneration) {
		switch generation {
		case .sandyBridge: self = .sandyBridge
		case .ivyBridge: self = .ivyBridge
		case .haswell: self = .haswell
		case .broadwell: self = .broadwell
		case .skylake, .kabyLake: self = .skylake
		case .coffeeLake: self = .coffeeLake
		case .iceLakeLP: self = .iceLakeLP
		}
	}

	var layout: FramebufferLayout {
		switch self {
		case .sandyBridge: return .sandyBridge
		case .ivyBridge: return .ivyBridge
		case .haswell: return .haswell
		case .broadwell: return .broadwell
		case .skylake: return .skylake
		case .coffeeLake: return .coffeeLake
		case .cannonLake: return .cannonLake
		case .iceLakeLP: return .iceLakeLP
		case .iceLakeHP: return .iceLakeHP
		}
	}

	/// The first platform ID of each table, used to find it in a framebuffer kext.
	var firstPlatformID: UInt32 {
		switch self {
		case .sandyBridge: return 0x0004_0201
		case .ivyBridge: return 0x0166_0000
		case .haswell: return 0x0C06_0000
		case .broadwell: return 0x1606_0000
		case .skylake: return 0x191E_0000
		case .coffeeLake: return 0x3EA5_0009
		case .cannonLake: return 0x5A51_0009
		case .iceLakeLP, .iceLakeHP: return 0xFF05_0000
		}
	}

	var isIceLake: Bool { return self == .iceLakeLP || self == .iceLakeHP }
}

struct FramebufferLayout {
	/// A field's byte offset and size.
	struct Field {
		let offset: Int
		let size: Int
	}

	let size: Int
	let framebufferID: Field?
	let pchType: Field?
	let modelNameAddress: Field?
	let mobile: Field
	let pipeCount: Field
	let portCount: Field
	let memoryCount: Field
	let stolenMemory: Field?
	let framebufferMemory: Field?
	let cursorMemory: Field?
	let unifiedMemory: Field?
	let backlightFrequency: Field?
	let backlightMax: Field?
	let flags: Field?
	let bttIndexSlice: Field?
	let bttIndexNormal: Field?
	let bttIndexHDMI: Field?
	let camellia: Field?
	let numTransactionsThreshold: Field?
	let videoTurboFrequency: Field?
	let rc6Threshold: Field?
	let bttArraySlice: Field?
	let bttArrayNormal: Field?
	let bttArrayHDMI: Field?
	let sliceCount: Field?
	let euCount: Field?
	let connectorsOffset: Int
	let connectorCount: Int
	/// 12 bytes before Ice Lake, 24 after (every connector field widened to 32 bits).
	let connectorSize: Int

	var isWideConnector: Bool { return connectorSize == 24 }

	private static func f(_ offset: Int, _ size: Int = 4) -> Field { return Field(offset: offset, size: size) }

	static let sandyBridge = FramebufferLayout(
		size: 60, framebufferID: nil, pchType: nil, modelNameAddress: nil,
		mobile: f(0, 1), pipeCount: f(1, 1), portCount: f(2, 1), memoryCount: f(3, 1),
		stolenMemory: nil, framebufferMemory: nil, cursorMemory: nil, unifiedMemory: nil,
		backlightFrequency: f(4), backlightMax: f(8), flags: nil,
		bttIndexSlice: nil, bttIndexNormal: nil, bttIndexHDMI: nil, camellia: nil,
		numTransactionsThreshold: nil, videoTurboFrequency: nil, rc6Threshold: nil,
		bttArraySlice: nil, bttArrayNormal: nil, bttArrayHDMI: nil, sliceCount: nil, euCount: nil,
		connectorsOffset: 12, connectorCount: 4, connectorSize: 12)

	static let ivyBridge = FramebufferLayout(
		size: 200, framebufferID: f(0), pchType: nil, modelNameAddress: nil,
		mobile: f(4, 1), pipeCount: f(5, 1), portCount: f(6, 1), memoryCount: f(7, 1),
		stolenMemory: f(8), framebufferMemory: f(12), cursorMemory: nil, unifiedMemory: f(16),
		backlightFrequency: f(20), backlightMax: f(24), flags: nil,
		bttIndexSlice: nil, bttIndexNormal: nil, bttIndexHDMI: nil, camellia: nil,
		numTransactionsThreshold: nil, videoTurboFrequency: nil, rc6Threshold: nil,
		bttArraySlice: nil, bttArrayNormal: nil, bttArrayHDMI: nil, sliceCount: nil, euCount: nil,
		connectorsOffset: 48, connectorCount: 4, connectorSize: 12)

	static let haswell = FramebufferLayout(
		size: 112, framebufferID: f(0), pchType: nil, modelNameAddress: nil,
		mobile: f(4, 1), pipeCount: f(5, 1), portCount: f(6, 1), memoryCount: f(7, 1),
		stolenMemory: f(8), framebufferMemory: f(12), cursorMemory: f(16), unifiedMemory: f(20),
		backlightFrequency: f(24), backlightMax: f(28), flags: f(88),
		bttIndexSlice: nil, bttIndexNormal: nil, bttIndexHDMI: nil, camellia: f(95, 1),
		numTransactionsThreshold: f(100), videoTurboFrequency: f(104), rc6Threshold: nil,
		bttArraySlice: nil, bttArrayNormal: nil, bttArrayHDMI: nil, sliceCount: nil, euCount: nil,
		connectorsOffset: 40, connectorCount: 4, connectorSize: 12)

	static let broadwell = FramebufferLayout(
		size: 136, framebufferID: f(0), pchType: nil, modelNameAddress: nil,
		mobile: f(4, 1), pipeCount: f(5, 1), portCount: f(6, 1), memoryCount: f(7, 1),
		stolenMemory: f(8), framebufferMemory: f(12), cursorMemory: nil, unifiedMemory: f(16),
		backlightFrequency: f(20), backlightMax: f(24), flags: f(88),
		bttIndexSlice: nil, bttIndexNormal: nil, bttIndexHDMI: nil, camellia: f(96),
		numTransactionsThreshold: f(124), videoTurboFrequency: f(128), rc6Threshold: f(132),
		bttArraySlice: nil, bttArrayNormal: nil, bttArrayHDMI: nil, sliceCount: nil, euCount: nil,
		connectorsOffset: 40, connectorCount: 4, connectorSize: 12)

	static let skylake = FramebufferLayout(
		size: 184, framebufferID: f(0), pchType: f(4), modelNameAddress: f(8, 8),
		mobile: f(16, 1), pipeCount: f(17, 1), portCount: f(18, 1), memoryCount: f(19, 1),
		stolenMemory: f(20), framebufferMemory: f(24), cursorMemory: nil, unifiedMemory: f(28),
		backlightFrequency: f(32), backlightMax: f(36), flags: f(96),
		bttIndexSlice: f(100, 1), bttIndexNormal: f(101, 1), bttIndexHDMI: f(102, 1), camellia: f(104),
		numTransactionsThreshold: f(132), videoTurboFrequency: f(136), rc6Threshold: nil,
		bttArraySlice: f(144, 8), bttArrayNormal: f(152, 8), bttArrayHDMI: f(160, 8), sliceCount: f(168), euCount: f(172),
		connectorsOffset: 48, connectorCount: 4, connectorSize: 12)

	static let coffeeLake = FramebufferLayout(
		size: 176, framebufferID: f(0), pchType: f(4), modelNameAddress: f(8, 8),
		mobile: f(16, 1), pipeCount: f(17, 1), portCount: f(18, 1), memoryCount: f(19, 1),
		stolenMemory: f(20), framebufferMemory: f(24), cursorMemory: nil, unifiedMemory: f(28),
		backlightFrequency: nil, backlightMax: nil, flags: f(88),
		bttIndexSlice: f(92, 1), bttIndexNormal: f(93, 1), bttIndexHDMI: f(94, 1), camellia: f(96),
		numTransactionsThreshold: f(124), videoTurboFrequency: f(128), rc6Threshold: nil,
		bttArraySlice: f(136, 8), bttArrayNormal: f(144, 8), bttArrayHDMI: f(152, 8), sliceCount: f(160), euCount: f(164),
		connectorsOffset: 40, connectorCount: 4, connectorSize: 12)

	static let cannonLake = FramebufferLayout(
		size: 344, framebufferID: f(0), pchType: f(4), modelNameAddress: f(8, 8),
		mobile: f(16, 1), pipeCount: f(17, 1), portCount: f(18, 1), memoryCount: f(19, 1),
		stolenMemory: f(20), framebufferMemory: f(24), cursorMemory: nil, unifiedMemory: f(28),
		backlightFrequency: nil, backlightMax: nil, flags: f(88),
		bttIndexSlice: f(92, 1), bttIndexNormal: f(93, 1), bttIndexHDMI: f(94, 1), camellia: f(288),
		numTransactionsThreshold: f(316), videoTurboFrequency: f(320), rc6Threshold: nil,
		bttArraySlice: f(136, 8), bttArrayNormal: f(144, 8), bttArrayHDMI: f(152, 8), sliceCount: f(324), euCount: f(328),
		connectorsOffset: 40, connectorCount: 4, connectorSize: 12)

	static let iceLakeLP = FramebufferLayout(
		size: 280, framebufferID: f(0), pchType: f(4), modelNameAddress: f(8, 8),
		mobile: f(16, 1), pipeCount: f(17, 1), portCount: f(18, 1), memoryCount: f(19, 1),
		stolenMemory: f(20), framebufferMemory: f(24), cursorMemory: nil, unifiedMemory: f(28),
		backlightFrequency: nil, backlightMax: nil, flags: f(176),
		bttIndexSlice: nil, bttIndexNormal: nil, bttIndexHDMI: nil, camellia: f(240),
		numTransactionsThreshold: f(256), videoTurboFrequency: f(260), rc6Threshold: nil,
		bttArraySlice: nil, bttArrayNormal: nil, bttArrayHDMI: nil, sliceCount: f(264), euCount: f(268),
		connectorsOffset: 32, connectorCount: 6, connectorSize: 24)

	static let iceLakeHP = FramebufferLayout(
		size: 320, framebufferID: f(0), pchType: f(4), modelNameAddress: f(8, 8),
		mobile: f(16, 1), pipeCount: f(17, 1), portCount: f(18, 1), memoryCount: f(19, 1),
		stolenMemory: f(20), framebufferMemory: f(24), cursorMemory: nil, unifiedMemory: f(28),
		backlightFrequency: f(32), backlightMax: f(36), flags: f(120),
		bttIndexSlice: nil, bttIndexNormal: nil, bttIndexHDMI: nil, camellia: f(272),
		numTransactionsThreshold: f(300), videoTurboFrequency: f(304), rc6Threshold: nil,
		bttArraySlice: nil, bttArrayNormal: nil, bttArrayHDMI: nil, sliceCount: f(308), euCount: f(312),
		connectorsOffset: 48, connectorCount: 3, connectorSize: 24)
}

// MARK: - Values

enum ConnectorType: UInt32, CaseIterable {
	case zero = 0x0
	case dummy = 0x1
	case lvds = 0x2
	case digitalDVI = 0x4
	case svid = 0x8
	case vga = 0x10
	case displayPort = 0x400
	case hdmi = 0x800
	case analogDVI = 0x2000

	var name: String {
		switch self {
		case .zero: return "Zero"
		case .dummy: return "Dummy"
		case .lvds: return "LVDS"
		case .digitalDVI: return "DigitalDVI"
		case .svid: return "SVID"
		case .vga: return "VGA"
		case .displayPort: return "DP"
		case .hdmi: return "HDMI"
		case .analogDVI: return "AnalogDVI"
		}
	}
}

enum CamelliaVersion: UInt32, CaseIterable {
	case disabled = 0, v1 = 1, v2 = 2, v3 = 3, unsupported = 0xFF

	var name: String {
		switch self {
		case .disabled: return "Disabled"
		case .v1: return "V1"
		case .v2: return "V2"
		case .v3: return "V3"
		case .unsupported: return "Unsupported"
		}
	}
}

/// Framebuffer flag bits, in bit order (0x1, 0x2, 0x4...).
let framebufferFlagNames = [
	"FBAvoidFastLinkTraining", "FBFramebufferCommonMemory", "FBFramebufferCompression", "FBEnableSliceFeatures",
	"FBDynamicFBCEnable", "FBUseVideoTurbo", "FBForcePowerAlwaysConnected", "FBDisableHighBitrateMode2",
	"FBBoostPixelFrequencyLimit", "FBLimit4KSourceSize", "FBAlternatePWMIncrement1", "FBAlternatePWMIncrement2",
	"FBDisableFeatureIPS", "FBUnknownFlag_2000", "FBAllowConnectorRecover", "FBUnknownFlag_8000",
	"FBUnknownFlag_10000", "FBUnknownFlag_20000", "FBDisableGFMPPFM", "FBUnknownFlag_80000",
	"FBUnknownFlag_100000", "FBEnableDynamicCDCLK", "FBUnknownFlag_400000", "FBSupport5KSourceSize",
]

/// Connector flag bits, in bit order.
let connectorFlagNames = [
	"CNAlterAppertureRequirements", "CNUnknownFlag_2", "CNUnknownFlag_4", "CNConnectorAlwaysConnected",
	"CNUnknownFlag_10", "CNUnknownFlag_20", "CNDisableBlitTranslationTable", "CNUseMiscIoPowerWell",
	"CNUsePowerWell2", "CNUnknownFlag_200", "CNUnknownFlag_400", "CNIncreaseLaneCount",
	"CNUnknownFlag_1000", "CNUnknownFlag_2000", "CNUnknownFlag_4000", "CNUnknownFlag_8000",
]

struct Connector: Equatable {
	/// -1 (0xFF) disables the connector.
	var index: Int32
	var busID: UInt32
	var pipe: UInt32
	var type: UInt32
	var flags: UInt32

	var typeName: String {
		return ConnectorType(rawValue: type).map { L($0.name) } ?? String(format: "0x%08X", type)
	}
}

// MARK: - A single framebuffer record

/// One platform's framebuffer record, edited in place. Missing fields read as nil and ignore writes.
struct Framebuffer: Equatable {
	let kind: FramebufferKind
	var bytes: [UInt8]

	init(kind: FramebufferKind, bytes: [UInt8]) {
		self.kind = kind
		self.bytes = bytes
	}

	var layout: FramebufferLayout { return kind.layout }

	static func == (lhs: Framebuffer, rhs: Framebuffer) -> Bool {
		return lhs.bytes == rhs.bytes
	}

	func read(_ field: FramebufferLayout.Field?) -> UInt64? {
		guard let field = field else { return nil }
		return (0..<field.size).reduce(UInt64(0)) { $0 | UInt64(bytes[field.offset + $1]) << (8 * UInt64($1)) }
	}

	mutating func write(_ field: FramebufferLayout.Field?, _ value: UInt64) {
		guard let field = field else { return }
		for index in 0..<field.size {
			bytes[field.offset + index] = UInt8((value >> (8 * UInt64(index))) & 0xFF)
		}
	}

	func read32(_ field: FramebufferLayout.Field?) -> UInt32? { return read(field).map { UInt32(truncatingIfNeeded: $0) } }

	var framebufferID: UInt32? { get { return read32(layout.framebufferID) } set { write(layout.framebufferID, UInt64(newValue ?? 0)) } }
	var isMobile: Bool { get { return read(layout.mobile) != 0 } set { write(layout.mobile, newValue ? 1 : 0) } }
	var pipeCount: UInt32 { get { return read32(layout.pipeCount) ?? 0 } set { write(layout.pipeCount, UInt64(newValue)) } }
	var portCount: UInt32 { get { return read32(layout.portCount) ?? 0 } set { write(layout.portCount, UInt64(newValue)) } }
	var memoryCount: UInt32 { get { return read32(layout.memoryCount) ?? 0 } set { write(layout.memoryCount, UInt64(newValue)) } }
	var stolenMemory: UInt32? { get { return read32(layout.stolenMemory) } set { write(layout.stolenMemory, UInt64(newValue ?? 0)) } }
	var framebufferMemory: UInt32? { get { return read32(layout.framebufferMemory) } set { write(layout.framebufferMemory, UInt64(newValue ?? 0)) } }
	var cursorMemory: UInt32? { get { return read32(layout.cursorMemory) } set { write(layout.cursorMemory, UInt64(newValue ?? 0)) } }
	var unifiedMemory: UInt32? { get { return read32(layout.unifiedMemory) } set { write(layout.unifiedMemory, UInt64(newValue ?? 0)) } }
	var flags: UInt32? { get { return read32(layout.flags) } set { write(layout.flags, UInt64(newValue ?? 0)) } }
	var camellia: UInt32? { get { return read32(layout.camellia) } set { write(layout.camellia, UInt64(newValue ?? 0)) } }

	func connector(at index: Int) -> Connector {
		let base = layout.connectorsOffset + index * layout.connectorSize
		func value(_ offset: Int, _ size: Int) -> UInt32 {
			return (0..<size).reduce(UInt32(0)) { $0 | UInt32(bytes[base + offset + $1]) << (8 * UInt32($1)) }
		}
		if layout.isWideConnector {
			return Connector(index: Int32(bitPattern: value(0, 4)), busID: value(4, 4), pipe: value(8, 4), type: value(16, 4), flags: value(20, 4))
		}
		return Connector(index: Int32(Int8(bitPattern: UInt8(value(0, 1)))), busID: value(1, 1), pipe: value(2, 1), type: value(4, 4), flags: value(8, 4))
	}

	mutating func setConnector(_ connector: Connector, at index: Int) {
		let base = layout.connectorsOffset + index * layout.connectorSize
		func put(_ offset: Int, _ size: Int, _ value: UInt32) {
			for byte in 0..<size {
				bytes[base + offset + byte] = UInt8((value >> (8 * UInt32(byte))) & 0xFF)
			}
		}
		if layout.isWideConnector {
			put(0, 4, UInt32(bitPattern: connector.index))
			put(4, 4, connector.busID)
			put(8, 4, connector.pipe)
			put(16, 4, connector.type)
			put(20, 4, connector.flags)
		} else {
			put(0, 1, UInt32(UInt8(bitPattern: Int8(truncatingIfNeeded: connector.index))))
			put(1, 1, connector.busID)
			put(2, 1, connector.pipe)
			put(4, 4, connector.type)
			put(8, 4, connector.flags)
		}
	}

	var connectors: [Connector] {
		return (0..<layout.connectorCount).map(connector(at:))
	}

	/// The raw bytes of connector `index` (for "alldata" patches).
	func connectorBytes(_ index: Int, count: Int = 1) -> [UInt8] {
		let start = layout.connectorsOffset + index * layout.connectorSize
		return Array(bytes[start..<start + layout.connectorSize * count])
	}

	// MARK: Memory

	/// Total stolen memory macOS reserves (see AppleIntelFramebufferController::hwSetupBuffers).
	var totalStolenMemory: UInt32 {
		guard let stolen = stolenMemory, let fbMemory = framebufferMemory else { return 0 }
		let flags = self.flags ?? 0
		var total: UInt32 = 0x100000
		total = total &+ (flags & 0x2 != 0 ? stolen : stolen &* memoryCount)
		// Prior to Skylake the framebuffer memory counts unconditionally; afterwards only with compression.
		let countsFramebufferMemory = [.sandyBridge, .ivyBridge, .haswell, .broadwell].contains(kind) || flags & 0x4 != 0
		if countsFramebufferMemory {
			total = total &+ fbMemory
		}
		return total
	}

	var maxStolenMemory: UInt32 {
		return (stolenMemory ?? 0) &* memoryCount &+ (framebufferMemory ?? 0) &+ 0x100000
	}

	var totalCursorMemory: UInt32 { return pipeCount &* 0x80000 }

	var maxOverallMemory: UInt32 { return totalCursorMemory &+ maxStolenMemory &+ portCount &* 0x1000 }
}

enum ByteFormatting {
	/// "19 MB", "512 KB (524800 bytes)", "64 bytes".
	static func memory(_ bytes: UInt32) -> String {
		if bytes >= 1024 * 1024 {
			return bytes % (1024 * 1024) == 0 ? "\(bytes / 1024 / 1024) MB" : "\(bytes / 1024 / 1024) MB (\(bytes) bytes)"
		}
		if bytes >= 1024 {
			return bytes % 1024 == 0 ? "\(bytes / 1024) KB" : "\(bytes / 1024) KB (\(bytes) bytes)"
		}
		return "\(bytes) bytes"
	}

	/// Parses "19 MB", "512 KB", "1048576" or "0x100000".
	static func parseMemory(_ text: String) -> UInt32? {
		let parts = text.trimmingCharacters(in: .whitespaces).split(separator: " ")
		guard let first = parts.first, let number = String(first).hexOrDecimalValue else { return nil }
		let unit = parts.count > 1 ? parts[1].uppercased() : ""
		switch unit {
		case "MB": return UInt32(truncatingIfNeeded: number * 1024 * 1024)
		case "KB": return UInt32(truncatingIfNeeded: number * 1024)
		default: return UInt32(truncatingIfNeeded: number)
		}
	}
}
