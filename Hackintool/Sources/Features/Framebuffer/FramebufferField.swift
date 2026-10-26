//
//  FramebufferField.swift
//  Hackintool
//
//  The editable fields of a framebuffer record, how they're shown and parsed,
//  and a text report of a whole table.
//

import Foundation

enum FramebufferField: CaseIterable {
	case framebufferID, modelNameAddress, mobile, pipeCount, portCount, memoryCount
	case stolenMemory, framebufferMemory, cursorMemory, unifiedMemory, backlightFrequency, backlightMax
	case flags, bttIndexSlice, bttIndexNormal, bttIndexHDMI, camellia, numTransactionsThreshold, videoTurboFrequency
	case bttArraySlice, bttArrayNormal, bttArrayHDMI, sliceCount, euCount

	/// The names the original tool used (also the localization keys).
	var name: String {
		switch self {
		case .framebufferID: return "FramebufferID"
		case .modelNameAddress: return "ModelNameAddr"
		case .mobile: return "Mobile"
		case .pipeCount: return "PipeCount"
		case .portCount: return "PortCount"
		case .memoryCount: return "FBMemoryCount"
		case .stolenMemory: return "StolenMemorySize"
		case .framebufferMemory: return "FramebufferMemorySize"
		case .cursorMemory: return "CursorMemorySize"
		case .unifiedMemory: return "UnifiedMemorySize"
		case .backlightFrequency: return "BacklightFrequency"
		case .backlightMax: return "BacklightMax"
		case .flags: return "Flags"
		case .bttIndexSlice: return "BTTableOffsetIndexSlice"
		case .bttIndexNormal: return "BTTableOffsetIndexNormal"
		case .bttIndexHDMI: return "BTTableOffsetIndexHDMI"
		case .camellia: return "CamelliaVersion"
		case .numTransactionsThreshold: return "NumTransactionsThreshold"
		case .videoTurboFrequency: return "VideoTurboFreq"
		case .bttArraySlice: return "BTTArraySliceAddr"
		case .bttArrayNormal: return "BTTArrayNormalAddr"
		case .bttArrayHDMI: return "BTTArrayHDMIAddr"
		case .sliceCount: return "SliceCount"
		case .euCount: return "EuCount"
		}
	}

	func layoutField(_ layout: FramebufferLayout) -> FramebufferLayout.Field? {
		switch self {
		case .framebufferID: return layout.framebufferID
		case .modelNameAddress: return layout.modelNameAddress
		case .mobile: return layout.mobile
		case .pipeCount: return layout.pipeCount
		case .portCount: return layout.portCount
		case .memoryCount: return layout.memoryCount
		case .stolenMemory: return layout.stolenMemory
		case .framebufferMemory: return layout.framebufferMemory
		case .cursorMemory: return layout.cursorMemory
		case .unifiedMemory: return layout.unifiedMemory
		case .backlightFrequency: return layout.backlightFrequency
		case .backlightMax: return layout.backlightMax
		case .flags: return layout.flags
		case .bttIndexSlice: return layout.bttIndexSlice
		case .bttIndexNormal: return layout.bttIndexNormal
		case .bttIndexHDMI: return layout.bttIndexHDMI
		case .camellia: return layout.camellia
		case .numTransactionsThreshold: return layout.numTransactionsThreshold
		case .videoTurboFrequency: return layout.videoTurboFrequency
		case .bttArraySlice: return layout.bttArraySlice
		case .bttArrayNormal: return layout.bttArrayNormal
		case .bttArrayHDMI: return layout.bttArrayHDMI
		case .sliceCount: return layout.sliceCount
		case .euCount: return layout.euCount
		}
	}

	private var isMemory: Bool {
		return [.stolenMemory, .framebufferMemory, .cursorMemory, .unifiedMemory].contains(self)
	}

	private var isHex: Bool {
		return [.framebufferID, .modelNameAddress, .flags, .bttIndexSlice, .bttIndexNormal, .bttIndexHDMI, .bttArraySlice, .bttArrayNormal, .bttArrayHDMI].contains(self)
	}

	func display(_ framebuffer: Framebuffer) -> String? {
		guard let field = layoutField(framebuffer.layout), let value = framebuffer.read(field) else { return nil }
		switch self {
		case .mobile: return L(value != 0 ? "Yes" : "No")
		case .camellia: return CamelliaVersion(rawValue: UInt32(value)).map { L($0.name) } ?? String(value)
		case .backlightFrequency, .backlightMax: return "\(value) Hz"
		default:
			if isMemory {
				return ByteFormatting.memory(UInt32(truncatingIfNeeded: value))
			}
			if isHex {
				return String(format: "0x%0\(field.size * 2)llX", value)
			}
			return String(value)
		}
	}

	/// Parses edited text back into the record; returns false if it couldn't be understood.
	@discardableResult
	func parse(_ text: String, into framebuffer: inout Framebuffer) -> Bool {
		guard let field = layoutField(framebuffer.layout) else { return false }
		let trimmed = text.trimmingCharacters(in: .whitespaces)
		let value: UInt64?
		switch self {
		case .mobile:
			value = [L("Yes").lowercased(), "yes", "1", "true"].contains(trimmed.lowercased()) ? 1 : 0
		case .camellia:
			value = CamelliaVersion.allCases.first { L($0.name).caseInsensitiveCompare(trimmed) == .orderedSame }.map { UInt64($0.rawValue) } ?? trimmed.hexOrDecimalValue
		case .backlightFrequency, .backlightMax:
			value = trimmed.replacingOccurrences(of: "Hz", with: "").trimmingCharacters(in: .whitespaces).hexOrDecimalValue
		default:
			if isMemory {
				value = ByteFormatting.parseMemory(trimmed).map(UInt64.init)
			} else if isHex {
				value = UInt64(trimmed.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive), radix: 16)
			} else {
				value = trimmed.hexOrDecimalValue
			}
		}
		guard let parsed = value else { return false }
		framebuffer.write(field, parsed)
		return true
	}
}

extension FramebufferTable {
	/// A human-readable listing of every platform in the table (File ▸ Export ▸ Framebuffer Text).
	func report() -> String {
		var lines: [String] = []
		for (index, id) in platformIDs.enumerated() where id != 0xFFFF_FFFF {
			let framebuffer = original[index]
			let noFramebufferMemory = (framebuffer.framebufferMemory ?? 0) == 0 ? ", no fbmem" : ""
			lines.append(String(format: "0x%08X (%@, %d connectors%@)", id, framebuffer.isMobile ? "mobile" : "desktop", framebuffer.portCount, noFramebufferMemory))
		}
		for (index, id) in platformIDs.enumerated() where id != 0xFFFF_FFFF {
			let framebuffer = original[index]
			let memory = { (value: UInt32?) in value.map { ByteFormatting.memory($0) } ?? "-" }
			lines.append("")
			var header = String(format: "ID: %08X", id)
			if framebuffer.stolenMemory != nil {
				header += ", STOLEN: \(memory(framebuffer.stolenMemory)), FBMEM: \(memory(framebuffer.framebufferMemory)), VRAM: \(memory(framebuffer.unifiedMemory))"
			}
			if let flags = framebuffer.flags {
				header += String(format: ", Flags: 0x%08X", flags)
			}
			lines.append(header)
			lines.append("TOTAL STOLEN: \(ByteFormatting.memory(framebuffer.totalStolenMemory)), TOTAL CURSOR: \(ByteFormatting.memory(framebuffer.totalCursorMemory)), MAX STOLEN: \(ByteFormatting.memory(framebuffer.maxStolenMemory)), MAX OVERALL: \(ByteFormatting.memory(framebuffer.maxOverallMemory))")
			if let deviceID = FramebufferTable.gpuDeviceID(for: id, generation: generation) {
				lines.append(String(format: "GPU Name: %@ (0x%08X)", FramebufferTable.gpuName(for: id, generation: generation) ?? "???", deviceID))
			}
			lines.append("Model Name(s): \(FramebufferTable.modelNames(for: id))")
			var details: [String] = []
			if let camellia = framebuffer.camellia {
				details.append("Camellia: " + (CamelliaVersion(rawValue: camellia)?.name ?? String(camellia)))
			}
			if let frequency = framebuffer.read32(framebuffer.layout.backlightFrequency), let maximum = framebuffer.read32(framebuffer.layout.backlightMax) {
				details.append("Freq: \(frequency) Hz, FreqMax: \(maximum) Hz")
			}
			if !details.isEmpty {
				lines.append(details.joined(separator: ", "))
			}
			lines.append("Mobile: \(framebuffer.isMobile ? 1 : 0), PipeCount: \(framebuffer.pipeCount), PortCount: \(framebuffer.portCount), FBMemoryCount: \(framebuffer.memoryCount)")
			let ports = Int(framebuffer.portCount)
			for connector in framebuffer.connectors.prefix(ports) {
				lines.append(String(format: "[%d] busID: 0x%02X, pipe: %d, type: 0x%08X, flags: 0x%08X - %@", connector.index, connector.busID, connector.pipe, connector.type, connector.flags, connector.typeName))
			}
			for index in 0..<min(ports, framebuffer.layout.connectorCount) {
				lines.append(Framebuffer.hexDump(framebuffer.connectorBytes(index), wordSize: 4))
			}
		}
		return lines.joined(separator: "\n") + "\n"
	}

	/// The modified records back to back, as in the kext (File ▸ Export ▸ Framebuffer Binary).
	var binary: Data {
		return Data(modified.flatMap { $0.bytes })
	}
}

extension Framebuffer {
	/// "02040900 00040000 87000000": bytes grouped in fours, in memory order.
	static func hexDump(_ bytes: [UInt8], wordSize: Int) -> String {
		return stride(from: 0, to: bytes.count, by: wordSize).map { start in
			bytes[start..<min(start + wordSize, bytes.count)].map { String(format: "%02X", $0) }.joined()
		}.joined(separator: " ")
	}
}
