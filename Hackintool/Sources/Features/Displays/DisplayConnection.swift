//
//  DisplayConnection.swift
//  Hackintool
//
//  How each display is connected (HDMI, DP, DVI...). Displays on the Intel IGPU take the
//  type of their framebuffer connector, and AMD ones the connector-type their framebuffer
//  publishes; others fall back to what the display's EDID declares.
//

import Foundation

struct DisplayConnections {
	/// Connector types of this Mac's Intel framebuffer, by port-number.
	private let intelPortTypes: [UInt32: UInt32]

	init() {
		intelPortTypes = DisplayConnections.loadIntelPortTypes()
	}

	/// "HDMI", "DP", "LVDS"..., or "" when it can't be told.
	func name(for display: Display) -> String {
		if display.videoID & 0xFFFF == PCIVendor.intel, let type = intelPortTypes[display.port] {
			return ConnectorType(rawValue: type).map { L($0.name) } ?? String(format: "0x%08X", type)
		}
		if display.videoID & 0xFFFF == PCIVendor.amd, let type = display.connectorType,
		   let name = DisplayConnections.amdConnectorNames[type] {
			return L(name)
		}
		return display.edid.flatMap(EDID.init)?.videoInterface ?? ""
	}

	/// AMD connector types, as in WhateverGreen's RADConnectors::ConnectorType.
	private static let amdConnectorNames: [UInt32: String] = [
		0x2: "LVDS", 0x4: "DVI", 0x8: "S-Video", 0x10: "VGA", 0x400: "DP", 0x800: "HDMI", 0x2000: "DVI-A",
	]

	/// The running platform ID's connectors, with the IGPU's framebuffer patches applied, keyed by
	/// the port-number each gets: 0 for the panel, otherwise its index + 4 (+ 3 on Sandy/Ivy Bridge),
	/// as in AppleIntelFramebufferController::MapFBToPort.
	private static func loadIntelPortTypes() -> [UInt32: UInt32] {
		guard let generation = Machine.shared.intelGeneration, let platformID = Machine.shared.platformID,
		      let table = FramebufferTable.load(generation, from: .installedKext),
		      let index = table.index(of: platformID) else { return [:] }
		if let igpu = Machine.igpuEntry() {
			FramebufferPatcher.applyProperties(igpu.properties, to: table, at: index, updatesSettings: false)
		}
		let offset: UInt32 = [.sandyBridge, .ivyBridge].contains(generation) ? 3 : 4
		var types: [UInt32: UInt32] = [:]
		for connector in table.modified[index].connectors where connector.index >= 0 {
			let port = connector.index == 0 ? 0 : UInt32(connector.index) + offset
			if types[port] == nil {
				types[port] = connector.type
			}
		}
		return types
	}
}

extension EDID {
	/// The input a digital display declares: EDID 1.4's video interface field, otherwise an HDMI
	/// vendor-specific data block (IEEE OUI 00-0C-03) in a CEA-861 extension. Analog inputs are VGA.
	var videoInterface: String? {
		let input = bytes[EDID.basicParamsOffset]
		guard input & 0x80 != 0 else { return L("VGA") }
		if bytes[18] == 1 && bytes[19] >= 4 {
			switch input & 0x0F {
			case 1: return L("DVI")
			case 2, 3: return L("HDMI")
			case 5: return L("DP")
			default: break
			}
		}
		var block = 128
		while block + 128 <= bytes.count {
			if bytes[block] == 0x02 {
				// Data blocks run from byte 4 up to the detailed timings at byte 2's offset.
				let end = block + min(Int(bytes[block + 2]), 127)
				var offset = block + 4
				while offset < end {
					let tag = bytes[offset] >> 5
					let length = Int(bytes[offset] & 0x1F)
					if tag == 3 && length >= 3 && offset + 3 < end && Array(bytes[offset + 1...offset + 3]) == [0x03, 0x0C, 0x00] {
						return L("HDMI")
					}
					offset += 1 + length
				}
			}
			block += 128
		}
		return nil
	}
}
