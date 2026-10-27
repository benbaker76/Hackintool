//
//  SampleData.swift
//  Hackintool
//
//  Debug builds only: a made-up Comet Lake desktop (Z490, i9-10900K, UHD 630 and an
//  RX 6600 XT) for checking layouts on machines with nothing to show, such as Apple
//  Silicon, and for README screenshots that don't expose anyone's serials.
//
//    HACKINTOOL_SAMPLE=1 Hackintool.app/Contents/MacOS/Hackintool
//
//  Each data source returns these instead of reading the hardware when it's set.
//

#if DEBUG
import Cocoa

enum SampleData {
	static let isEnabled = ProcessInfo.processInfo.environment["HACKINTOOL_SAMPLE"] != nil

	// MARK: Machine

	static let modelIdentifier = "iMac20,2"
	static let serialNumber = "C02XXXXXXXXX"
	static let hostName = "Hackintosh"
	static let osName = "macOS Tahoe Version 26.1 (Build 25B78)"
	static let kernel = "Darwin 25.1.0 x86_64"
	static let cpu = "Intel(R) Core(TM) i9-10900K CPU @ 3.70GHz"
	static let memorySize = "32.00 GB"
	static let platformID: UInt32 = 0x3E9B_0007
	static let integratedGPU = IntegratedGPU(model: "Intel UHD Graphics 630", deviceID: 0x9BC5, vendorID: PCIVendor.intel,
	                                         vramSize: 1536, vramFree: 1_342_177_280)
	static let bootloader = Bootloader.openCore(bootedVersion: "1.0.5")

	static var systemGroups: [PropertyGroup] {
		return [
			PropertyGroup("System Info", [
				PropertyItem("Host", hostName),
				PropertyItem("OS", osName),
				PropertyItem("Kernel", kernel),
				PropertyItem("RAM", memorySize),
				PropertyItem("Model Identifier", modelIdentifier),
				PropertyItem("CPU", cpu),
				PropertyItem("Intel Generation", IntelGeneration.coffeeLake.displayName),
				PropertyItem("Platform ID", platformID.hex8),
				PropertyItem("Board ID", "Mac-63001698E7A34814"),
				PropertyItem("FW Version", "2075.0.0.0.0"),
				PropertyItem("Serial Number", serialNumber),
				PropertyItem("Hardware UUID", "00000000-0000-0000-0000-000000000000"),
				PropertyItem("System ID", "00000000-0000-0000-0000-000000000000"),
				PropertyItem("ROM", "000000000000"),
				PropertyItem("Board Serial Number", "C02XXXXXXXXXXXXXX"),
				PropertyItem("VDA Decoder", L("Fully Supported")),
			]),
			PropertyGroup("IGPU", [
				PropertyItem("GPU Name", "Intel UHD Graphics 630"),
				PropertyItem("GPU Device ID", UInt32(0x9BC5_8086).hex8),
				PropertyItem("Total VRAM", "1536 MB"),
				PropertyItem("Free VRAM", "1280 MB"),
				PropertyItem("Quartz Extreme (QE/CI)", L("Yes")),
				PropertyItem("Metal Supported", L("Yes")),
				PropertyItem("Metal Device Name", "Intel(R) UHD Graphics 630"),
				PropertyItem("Metal Default Device", L("No")),
				PropertyItem("Metal Low Power", L("Yes")),
				PropertyItem("Metal Headless", L("No")),
			]),
			PropertyGroup("GFX0", [
				PropertyItem("GPU Name", "AMD Radeon RX 6600 XT"),
				PropertyItem("GPU Device ID", UInt32(0x73FF_1002).hex8),
				PropertyItem("Quartz Extreme (QE/CI)", L("Yes")),
				PropertyItem("Metal Supported", L("Yes")),
				PropertyItem("Metal Device Name", "AMD Radeon RX 6600 XT"),
				PropertyItem("Metal Default Device", L("Yes")),
				PropertyItem("Metal Low Power", L("No")),
				PropertyItem("Metal Headless", L("No")),
			]),
		]
	}

	// MARK: PCI

	private static let root = "/PC00@0"
	private static let rootPath = "PciRoot(0x0)"

	static var pciDevices: [PCIDevice] {
		IDDatabase.pci.loadIfNeeded()
		// (name, ioName, vendor, device, subvendor, subdevice, class, bus:dev.fn, parents, kext)
		let rows: [(String, String, UInt32, UInt32, UInt32, UInt32, UInt32, String, [(String, UInt32, UInt32)], String?)] = [
			("IGPU", "display", 0x8086, 0x9BC5, 0x1458, 0xD000, 0x030000, "00:02.0", [], "com.apple.driver.AppleIntelCFLGraphicsFramebuffer"),
			("PEG0", "pci-bridge", 0x8086, 0x1901, 0x1458, 0x5000, 0x060400, "00:01.0", [], "com.apple.iokit.IOPCIFamily"),
			("GFX0", "display", 0x1002, 0x73FF, 0x1DA2, 0xE445, 0x030000, "03:00.0", [("PEG0", 1, 0), ("pci-bridge", 0, 0), ("pci-bridge", 0, 0)], "com.apple.kext.AMDRadeonX6000Framebuffer"),
			("HDAU", "pci1002,ab28", 0x1002, 0xAB28, 0x1002, 0xAB28, 0x040300, "03:00.1", [("PEG0", 1, 0), ("pci-bridge", 0, 0), ("pci-bridge", 0, 0)], "com.apple.driver.AppleGFXHDA"),
			("IMEI", "pci8086,6e0", 0x8086, 0x06E0, 0x1458, 0x1C3A, 0x078000, "00:16.0", [], nil),
			("XHC", "pci8086,6ed", 0x8086, 0x06ED, 0x1458, 0x5007, 0x0C0330, "00:14.0", [], "com.apple.driver.usb.AppleUSBXHCIPCI"),
			("SATA", "pci8086,6d2", 0x8086, 0x06D2, 0x1458, 0xB005, 0x010601, "00:17.0", [], "com.apple.driver.AppleAHCIPort"),
			("RP09", "pci-bridge", 0x8086, 0x06B0, 0x1458, 0x5001, 0x060400, "00:1B.0", [], "com.apple.iokit.IOPCIFamily"),
			("ANS1", "pci144d,a80a", 0x144D, 0xA80A, 0x144D, 0xA801, 0x010802, "04:00.0", [("RP09", 0x1B, 0)], "com.apple.iokit.IONVMeFamily"),
			("RP05", "pci-bridge", 0x8086, 0x06AC, 0x1458, 0x5001, 0x060400, "00:1C.4", [], "com.apple.iokit.IOPCIFamily"),
			("ETH0", "pci8086,15f3", 0x8086, 0x15F3, 0x1458, 0xE000, 0x020000, "05:00.0", [("RP05", 0x1C, 4)], "com.apple.driver.AppleIntelI210Ethernet"),
			("RP07", "pci-bridge", 0x8086, 0x06BE, 0x1458, 0x5001, 0x060400, "00:1C.6", [], "com.apple.iokit.IOPCIFamily"),
			("ARPT", "pci14e4,43a0", 0x14E4, 0x43A0, 0x106B, 0x0111, 0x028000, "06:00.0", [("RP07", 0x1C, 6)], "com.apple.driver.AirPort.BrcmNIC"),
			("LPCB", "pci8086,685", 0x8086, 0x0685, 0x1458, 0x5001, 0x060100, "00:1F.0", [], "com.apple.driver.AppleLPC"),
			("HDEF", "pci8086,6c8", 0x8086, 0x06C8, 0x1458, 0xA0C3, 0x040300, "00:1F.3", [], "com.apple.driver.AppleHDAController"),
			("SBUS", "pci8086,6a3", 0x8086, 0x06A3, 0x1458, 0x5001, 0x0C0500, "00:1F.4", [], "com.apple.driver.AppleSMBusPCI"),
		]
		return rows.map { name, ioName, vendor, device, subVendor, subDevice, classCode, bdf, parents, kext in
			let parts = bdf.split(whereSeparator: { ":.".contains($0) }).compactMap { UInt32($0, radix: 16) }
			let (dev, fn) = parents.isEmpty ? (parts[1], parts[2]) : (UInt32(0), parts[2])
			func node(_ name: String, _ dev: UInt32, _ fn: UInt32) -> String { return fn == 0 ? String(format: "%@@%X", name, dev) : String(format: "%@@%X,%X", name, dev, fn) }
			let acpi = ([root] + parents.map { node($0.0, $0.1, $0.2) } + [node(name, dev, fn)]).joined(separator: "/")
			let path = ([rootPath] + parents.map { String(format: "Pci(0x%X,0x%X)", $0.1, $0.2) } + [String(format: "Pci(0x%X,0x%X)", dev, fn)]).joined(separator: "/")
			return PCIDevice(registryName: name, ioName: ioName, servicePath: "IOService:/AppleACPIPlatformExpert/PC00@0/" + name,
			                 acpiPath: acpi, devicePath: path, slotName: "Internal@0,\(dev),\(fn)",
			                 vendorID: vendor, deviceID: device, subsystemVendorID: subVendor, subsystemID: subDevice,
			                 classCode: classCode, aspm: classCode >> 16 == 0x06 ? "L1" : L("Disabled"),
			                 model: ["IGPU": "Intel UHD Graphics 630", "GFX0": "AMD Radeon RX 6600 XT"][name], bundleID: kext, busDeviceFunction: bdf, address: dev << 16 | fn,
			                 shadowVendorID: vendor, shadowDeviceID: device).named(using: IDDatabase.pci)
		}
	}

	// MARK: Displays

	static var displays: [Display] {
		let igpu = pciDevices.first { $0.registryName == "IGPU" }
		let gfx0 = pciDevices.first { $0.registryName == "GFX0" }
		return [
			Display(name: "DELL U2723QE", index: 0, port: 0, vendorID: 0x10AC, productID: 0x4295, serialNumber: 0x4C53_4E31,
			        edid: edid(vendor: "DEL", product: 0x4295, name: "DELL U2723QE", timing: uhd), prefsKey: nil, isInternal: false,
			        videoPath: gfx0?.servicePath, videoID: 0x73FF_1002, displayID: nil),
			Display(name: "LG HDR QHD", index: 1, port: 5, vendorID: 0x1E6D, productID: 0x5B6F, serialNumber: 0x0001_E240,
			        edid: edid(vendor: "GSM", product: 0x5B6F, name: "LG HDR QHD", timing: qhd), prefsKey: nil, isInternal: false,
			        videoPath: igpu?.servicePath, videoID: 0x9BC5_8086, displayID: nil),
		]
	}

	/// 3840x2160 and 2560x1440 at 60 Hz (CVT reduced blanking) on a 27" panel.
	private static let uhd: [UInt8] = [0x4D, 0xD0, 0x00, 0xA0, 0xF0, 0x70, 0x3E, 0x80, 0x30, 0x20, 0x35, 0x00, 0x55, 0x50, 0x21, 0x00, 0x00, 0x1A]
	private static let qhd: [UInt8] = [0x56, 0x5E, 0x00, 0xA0, 0xA0, 0xA0, 0x29, 0x50, 0x30, 0x20, 0x35, 0x00, 0x55, 0x50, 0x21, 0x00, 0x00, 0x1A]

	/// A plausible EDID 1.4 base block with one detailed timing and a name.
	private static func edid(vendor: String, product: UInt16, name: String, timing: [UInt8]) -> Data {
		var bytes = [UInt8](repeating: 0, count: 128)
		bytes.replaceSubrange(0..<8, with: [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
		let letters = vendor.utf8.map { UInt16($0 - 0x40) & 0x1F }
		let manufacturer = letters[0] << 10 | letters[1] << 5 | letters[2]
		bytes[8] = UInt8(manufacturer >> 8)
		bytes[9] = UInt8(manufacturer & 0xFF)
		bytes[10] = UInt8(product & 0xFF)
		bytes[11] = UInt8(product >> 8)
		bytes[16] = 12
		bytes[17] = 33  // 2023
		bytes[18] = 1
		bytes[19] = 4
		bytes.replaceSubrange(20..<25, with: [0xB5, 0x3C, 0x22, 0x78, 0x3A])
		bytes.replaceSubrange(25..<35, with: [0x4F, 0xA5, 0xAE, 0x52, 0x51, 0x9D, 0x26, 0x10, 0x51, 0x54])
		for offset in stride(from: 38, to: 54, by: 2) {
			bytes[offset] = 0x01
			bytes[offset + 1] = 0x01
		}
		bytes.replaceSubrange(54..<72, with: timing)
		let range: [UInt8] = [0, 0, 0, 0xFD, 0, 0x30, 0x4C, 0x1E, 0x8C, 0x3C, 0x00, 0x0A, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20]
		bytes.replaceSubrange(72..<90, with: range)
		let text = Array((name + "\n").utf8.prefix(13)) + [UInt8](repeating: 0x20, count: max(0, 13 - name.utf8.count - 1))
		bytes.replaceSubrange(90..<108, with: [0, 0, 0, 0xFC, 0] + text)
		bytes.replaceSubrange(108..<126, with: [0, 0, 0, 0x10, 0] + [UInt8](repeating: 0, count: 13))
		bytes[127] = UInt8(truncatingIfNeeded: 256 - Int(bytes[0..<127].reduce(UInt8(0)) { $0 &+ $1 }))
		return Data(bytes)
	}

	// MARK: Sound

	static var audioDevices: [AudioDevice] {
		// Pin defaults of a typical ALC1220 desktop board.
		let pins: [(UInt8, UInt32)] = [
			(0x12, 0x40000000), (0x14, 0x01014010), (0x15, 0x01011012), (0x16, 0x01016011), (0x17, 0x01012014),
			(0x18, 0x01A19030), (0x19, 0x02A19040), (0x1A, 0x0181303F), (0x1B, 0x0221401F), (0x1D, 0x40400001), (0x1E, 0x01451120),
		]
		var verbs = Data()
		for (nid, value) in pins {
			for (command, shift) in [(UInt32(0x71C), UInt32(0)), (0x71D, 8), (0x71E, 16), (0x71F, 24)] {
				let verb = UInt32(nid) << 20 | command << 8 | (value >> shift & 0xFF)
				verbs.append(contentsOf: [UInt8(verb >> 24), UInt8(verb >> 16 & 0xFF), UInt8(verb >> 8 & 0xFF), UInt8(verb & 0xFF)])
			}
		}
		let realtek = AudioDevice(sampleClass: "AppleHDADriver", bundleID: "com.apple.driver.AppleHDA",
		                          deviceID: 0x8086_06C8, subDeviceID: 0x1458_A0C3, layoutID: 7,
		                          name: "Realtek ALC1220", manufacturer: "Realtek", modelID: 0x10EC_1220,
		                          codecID: 0x10EC_1220, codecRevisionID: 0x10_0003, hdaConfigDefault: [
		                          	"AFGLowPowerState": Data([0x03, 0x00, 0x00, 0x00]),
		                          	"BootConfigData": verbs,
		                          	"Codec": "ALC1220 for Gigabyte Z490 Vision D",
		                          	"CodecID": NSNumber(value: 0x10EC_1220),
		                          	"FuncGroup": NSNumber(value: 1),
		                          	"LayoutID": NSNumber(value: 7),
		                          	"WakeVerbReinit": true,
		                          ])
		let hdmi = AudioDevice(sampleClass: "AppleGFXHDAAudioDevice", bundleID: "com.apple.driver.AppleGFXHDA",
		                       deviceID: 0x1002_AB28, subDeviceID: 0x1002_AB28, layoutID: 0,
		                       name: "AMD Radeon RX 6600 XT", manufacturer: "AMD", modelID: 0x1002_AA01,
		                       codecID: 0x1002_AA01, codecRevisionID: 0x10_0700, hdaConfigDefault: nil)
		return [realtek, hdmi]
	}

	// MARK: USB

	static var usbControllers: [USBController] {
		return [USBController(name: "XHC", className: "AppleUSBXHCIPCI", deviceID: 0x06ED_8086, location: 0x14,
		                      servicePath: "IOService:/AppleACPIPlatformExpert/PC00@0/AppleACPIPCI/XHC@14/XHC@14000000",
		                      pciDebug: "0:20:0", vendorName: "Intel Corporation", deviceName: "Comet Lake USB 3.1 xHCI Host Controller")]
	}

	static var usbPorts: [USBPort] {
		// (name, port, connector, comment, active, device, speed)
		let rows: [(String, UInt32, USBConnector, String?, Bool, String?, Int?)] = [
			("HS01", 1, .usb3StandardA, "Rear I/O, top left", true, "USB Receiver", 1),
			("HS02", 2, .usb3StandardA, "Rear I/O, top right", true, nil, nil),
			("HS03", 3, .usb3StandardA, "Rear I/O, bottom left", true, nil, nil),
			("HS04", 4, .usb3StandardA, "Rear I/O, bottom right", true, nil, nil),
			("HS05", 5, .typeC, "Rear Type-C", true, nil, nil),
			("HS06", 6, .usb3StandardA, "Front panel", true, "USB2.0 Hub", 2),
			("HS07", 7, .usb3StandardA, "Front panel", true, nil, nil),
			("HS08", 8, .typeA, nil, false, nil, nil),
			("HS09", 9, .typeA, nil, false, nil, nil),
			("HS10", 10, .internal, "Fenvi Bluetooth", true, "Bluetooth USB Host Controller", 1),
			("HS11", 11, .internal, "RGB Fusion", true, "ITE Device(8297)", 1),
			("HS12", 12, .typeA, nil, false, nil, nil),
			("HS13", 13, .typeA, nil, false, nil, nil),
			("HS14", 14, .typeA, nil, false, nil, nil),
			("SS01", 17, .usb3StandardA, "Rear I/O, top left", true, nil, nil),
			("SS02", 18, .usb3StandardA, "Rear I/O, top right", true, "Samsung Portable SSD T7", 4),
			("SS03", 19, .usb3StandardA, "Rear I/O, bottom left", true, nil, nil),
			("SS04", 20, .usb3StandardA, "Rear I/O, bottom right", true, nil, nil),
			("SS05", 21, .typeC, "Rear Type-C", true, nil, nil),
			("SS06", 22, .usb3StandardA, "Front panel", true, nil, nil),
			("SS07", 23, .usb3StandardA, "Front panel", true, nil, nil),
			("SS08", 24, .usb3StandardA, nil, false, nil, nil),
		]
		return rows.map { name, port, connector, comment, active, device, speed in
			let location = port <= 15 ? port << 20 : (port >> 4) << 20 | (port & 0xF) << 16
			return USBPort(name: name, port: port, locationID: 0x1400_0000 | location, connector: connector.rawValue,
			               comment: comment, isActive: active, controllerName: "XHC", controllerID: 0x06ED_8086,
			               controllerLocation: 0x14, controllerClass: "AppleUSBXHCIPCI", hubName: nil, hubLocation: nil,
			               servicePath: nil, deviceName: device, deviceSpeed: speed,
			               portClass: name.hasPrefix("SS") ? "AppleUSB30XHCIPort" : "AppleUSB20XHCIPort")
		}
	}

	// MARK: Peripherals

	static let networkInterfaces = [
		NetworkInterface(bsdName: "en0", isBuiltIn: true, vendorID: 0x8086, deviceID: 0x15F3, vendorName: "Intel Corporation",
		                 deviceName: "Ethernet Controller I225-V", bundleID: "com.apple.driver.AppleIntelI210Ethernet"),
		NetworkInterface(bsdName: "en1", isBuiltIn: true, vendorID: 0x14E4, deviceID: 0x43A0, vendorName: "Broadcom Inc. and subsidiaries",
		                 deviceName: "BCM4360 802.11ac Dual Band Wireless Network Adapter", bundleID: "com.apple.driver.AirPort.BrcmNIC"),
	]

	static let bluetoothDevices = [
		BluetoothDevice(vendorID: 0x05AC, deviceID: 0x828D, vendorName: "Apple, Inc.", deviceName: "Bluetooth USB Host Controller", isFirmwareLoaded: true),
	]

	static let graphicsDevices = [
		GraphicsDevice(model: "AMD Radeon RX 6600 XT", framebuffer: "ATY,AMD,RadeonFramebuffer", portCount: 4, bundleID: "com.apple.kext.AMDRadeonX6000Framebuffer"),
		GraphicsDevice(model: "Intel UHD Graphics 630", framebuffer: platformID.hex8, portCount: 3, bundleID: "com.apple.driver.AppleIntelCFLGraphicsFramebuffer"),
	]

	static let storageDevices = [
		StorageDevice(model: "Samsung SSD 980 PRO 1TB", type: "PCI-Express", location: "Internal", blockSize: 4096, bundleID: "com.apple.iokit.IONVMeFamily"),
		StorageDevice(model: "WDC WD40EZAZ-00SF3B0", type: "SATA", location: "Internal", blockSize: 4096, bundleID: "com.apple.iokit.IOAHCIBlockStorage"),
		StorageDevice(model: "Samsung Portable SSD T7", type: "USB", location: "External", blockSize: 512, bundleID: "com.apple.iokit.IOUSBMassStorageDriver"),
	]

	// MARK: Boot

	static let powerSettings: [PowerSetting] = [
		("autorestart", "0"), ("disksleep", "10"), ("displaysleep", "10"), ("hibernatefile", "/var/vm/sleepimage"),
		("hibernatemode", "0"), ("networkoversleep", "0"), ("powernap", "0"), ("proximitywake", "0"), ("sleep", "0"),
		("standby", "0"), ("tcpkeepalive", "1"), ("ttyskeepawake", "1"), ("womp", "1"),
	].map { PowerSetting(name: $0.0, value: $0.1) }

	static let nvramVariables: [NVRAMVariable] = [
		NVRAMVariable(name: "boot-args", value: .data(Data("keepsyms=1 alcid=7 agdpmod=pikera".utf8))),
		NVRAMVariable(name: "csr-active-config", value: .data(Data([0x00, 0x00, 0x00, 0x00]))),
		NVRAMVariable(name: "prev-lang:kbd", value: .data(Data("en-US:0".utf8))),
		NVRAMVariable(name: "SystemAudioVolume", value: .data(Data([0x46]))),
		NVRAMVariable(name: "SystemAudioVolumeDB", value: .data(Data([0xF0]))),
		NVRAMVariable(name: "4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version", value: .data(Data("REL-105-2025-10-06".utf8))),
		NVRAMVariable(name: "4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14:UIScale", value: .data(Data([0x02]))),
		NVRAMVariable(name: "4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14:DefaultBackgroundColor", value: .data(Data([0x00, 0x00, 0x00, 0x00]))),
		NVRAMVariable(name: "bluetoothActiveControllerInfo", value: .data(Data([0x8D, 0x82, 0xAC, 0x05, 0x00, 0x00, 0x00, 0x00]))),
		NVRAMVariable(name: "run-efi-updater", value: .data(Data("No".utf8))),
		NVRAMVariable(name: "LocationServicesEnabled", value: .data(Data([0x01]))),
	]

	/// Loaded kext versions, keyed like KextCatalog.loadedKextVersions(); some are behind on purpose.
	static let loadedKextVersions: [String: String] = [
		"lilu": "1.7.1", "whatevergreen": "1.7.0", "applealc": "1.9.5", "virtualsmc": "1.3.7", "smcprocessor": "1.3.7",
		"smcsuperio": "1.3.7", "nvmefix": "1.1.3", "usbtoolbox": "1.1.1", "airportbrcmfixup": "2.1.9", "brcmpatchram3": "2.7.0",
		"restrictevents": "1.1.5", "featureunlock": "1.1.7", "cpufriend": "1.2.9",
	]

	/// What Check Versions would find, so some kexts show as needing an update.
	static let latestKextVersions: [String: String] = [
		"lilu": "1.7.2", "whatevergreen": "1.7.1", "applealc": "1.9.6", "nvmefix": "1.1.3", "restrictevents": "1.1.6",
	]
}

extension AudioDevice {
	init(sampleClass: String, bundleID: String, deviceID: UInt32, subDeviceID: UInt32, layoutID: UInt32,
	     name: String, manufacturer: String, modelID: UInt32, codecID: UInt32, codecRevisionID: UInt32,
	     hdaConfigDefault: [String: Any]?) {
		deviceClass = sampleClass
		self.bundleID = bundleID
		self.deviceID = deviceID
		self.subDeviceID = subDeviceID
		revisionID = 0
		alcLayoutID = layoutID
		audioDeviceName = name
		audioDeviceManufacturerName = manufacturer
		audioDeviceModelID = modelID
		self.codecID = codecID
		self.codecRevisionID = codecRevisionID
		self.hdaConfigDefault = hdaConfigDefault
		addNames()
	}
}
#endif
