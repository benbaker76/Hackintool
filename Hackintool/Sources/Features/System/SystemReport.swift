//
//  SystemReport.swift
//  Hackintool
//
//  Builds the System ▸ System page: host and firmware details, the decoded serial,
//  per-GPU acceleration support and the iMessage-related platform keys.
//

import Cocoa
import Metal

enum SystemReport {
	static func groups(pciDevices: [PCIDevice], displays: [Display]) -> [PropertyGroup] {
		var groups = [systemGroup()]
		if let serial = Machine.shared.serialNumber {
			groups.append(PropertyGroup("Serial Info", serialItems(MacSerial.decode(serial))))
		}
		groups += gpuGroups(pciDevices: pciDevices, displays: displays)
		groups.append(PropertyGroup("iMessage Keys", iMessageItems()))
		return groups
	}

	static func systemGroup() -> PropertyGroup {
		let machine = Machine.shared
		let deviceTree = IORegistryEntry(path: "IODeviceTree:/")
		let options = IORegistryEntry(path: "IODeviceTree:/options")
		let appleVariable = "4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14:"

		var items = [
			PropertyItem("Host", SystemInfo.hostName),
			PropertyItem("OS", SystemInfo.osName),
			PropertyItem("Kernel", SystemInfo.kernel),
			PropertyItem("RAM", SystemInfo.memorySize),
			PropertyItem("Model Identifier", machine.modelIdentifier),
			PropertyItem("CPU", SystemInfo.cpu),
			PropertyItem("Intel Generation", machine.intelGeneration?.name),
			PropertyItem("Platform ID", machine.platformID.map { $0.hex8 }),
			PropertyItem("Board ID", deviceTree?.string("board-id")),
			PropertyItem("FW Version", IORegistryEntry(path: "IODeviceTree:/rom")?.string("version")),
			PropertyItem("Serial Number", machine.serialNumber),
			PropertyItem("Hardware UUID", deviceTree?.string("IOPlatformUUID")),
			PropertyItem("System ID", systemID()),
			PropertyItem("ROM", options?.data(appleVariable + "ROM")?.hexString()),
			PropertyItem("Board Serial Number", options?.data(appleVariable + "MLB").flatMap { String(data: $0, encoding: .ascii) }),
		]
		items.append(PropertyItem("VDA Decoder", vdaDecoderStatus()))
		return PropertyGroup("System Info", items)
	}

	static func serialItems(_ decoded: MacSerial.Decoded?) -> [PropertyItem] {
		guard let decoded = decoded else {
			return [PropertyItem("Valid", L("Unlikely"))]
		}
		var items: [PropertyItem] = []
		if let country = decoded.country {
			items.append(PropertyItem("Country", country))
		}
		items.append(PropertyItem("Year", decoded.year))
		if let week = decoded.week {
			items.append(PropertyItem("Week", week))
		}
		items += [
			PropertyItem("Line", decoded.line),
			PropertyItem("Model", decoded.model),
			PropertyItem("Model Identifier", decoded.modelIdentifier),
			PropertyItem("Valid", L(decoded.isValid ? "Possibly" : "Unlikely")),
		]
		return items
	}

	/// The SMBIOS system UUID from IODeviceTree:/efi/platform, formatted as a UUID.
	private static func systemID() -> String? {
		guard let data = IORegistryEntry(path: "IODeviceTree:/efi/platform")?.data("system-id"), data.count == 16 else { return nil }
		var hex = data.hexString()
		for index in [20, 16, 12, 8] {
			hex.insert("-", at: hex.index(hex.startIndex, offsetBy: index))
		}
		return hex
	}

	private static func vdaDecoderStatus() -> String {
		let status = CreateDecoder()
		switch status {
		case 0: return L("Fully Supported")
		case -12470: return L("Not Supported")
		case -12472: return L("Configuration Error")
		case -12473: return L("Decoder Failed")
		default: return L("Unknown Status (%d)", Int(status))
		}
	}

	// MARK: GPUs

	private static func gpuGroups(pciDevices: [PCIDevice], displays: [Display]) -> [PropertyGroup] {
		return pciDevices.filter { $0.isDisplay }.map { device in
			var name = device.deviceName
			switch device.combinedID {
			case 0x1111_1234: name = "Apple Boch VGA"
			case 0x0000_1013: name = "Apple Cirrus GD5446"
			default: break
			}

			var items = [
				PropertyItem("GPU Name", name),
				PropertyItem("GPU Device ID", device.combinedID.hex8),
			]

			if let display = displays.first(where: { $0.videoPath == device.servicePath }), let displayID = display.displayID {
				if device.vendorID == PCIVendor.intel && device.acpiName == "IGPU", let igpu = Machine.shared.integratedGPU {
					items.append(PropertyItem("Total VRAM", "\(igpu.vramSize) MB"))
					items.append(PropertyItem("Free VRAM", "\(igpu.vramFree / (1024 * 1024)) MB"))
				}
				items.append(PropertyItem("Quartz Extreme (QE/CI)", yesNo(CGDisplayUsesOpenGLAcceleration(displayID) != 0)))

				let metalDevice = CGDirectDisplayCopyCurrentMetalDevice(displayID)
				items.append(PropertyItem("Metal Supported", yesNo(metalDevice != nil)))
				if let metalDevice = metalDevice {
					items += [
						PropertyItem("Metal Device Name", metalDevice.name),
						PropertyItem("Metal Default Device", yesNo(metalDevice.registryID == MTLCreateSystemDefaultDevice()?.registryID)),
						PropertyItem("Metal Low Power", yesNo(metalDevice.isLowPower)),
						PropertyItem("Metal Headless", yesNo(metalDevice.isHeadless)),
					]
				}
			}
			return PropertyGroup(device.acpiName, items)
		}
	}

	private static func yesNo(_ value: Bool) -> String {
		return L(value ? "Yes" : "No")
	}

	// MARK: iMessage

	/// Platform keys macOS publishes on IOPower:/ that iMessage and FaceTime activation rely on.
	private static func iMessageItems() -> [PropertyItem] {
		let power = IORegistryEntry(path: "IOPower:/")
		return ["Gq3489ugfi", "Fyp98tpgj", "kbjfrfpoJU", "oycqAZloTNDm", "abKPld1EcMni"].map { key in
			PropertyItem(key, power?.data(key)?.hexString())
		}
	}
}
