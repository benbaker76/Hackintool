//
//  USBMapExport.swift
//  Hackintool
//
//  Writing the port map as a codeless USBPorts.kext (plus SSDT-USBX for port power),
//  reading one back, and the ACPI renames some controllers need.
//
//  The kext follows the layout CorpNewt's USBMap produces: one uniquely named
//  personality per controller (or internal hub), matched by the controller's
//  pcidebug, path or name, merging a "ports" dictionary into it.
//

import Cocoa

enum USBMapExport {
	/// macOS caps a controller at 15 ports; more are silently ignored.
	static let portLimit = 15

	/// Controller names macOS's own USB personalities match; a hack using them gets Apple's port map instead.
	static let reservedControllerNames: [String: String] = ["XHC1": "XHC2", "EHC1": "EH01", "EHC2": "EH02"]

	// MARK: Kext

	static func kextInfoPlist(ports: [USBPort], controllers: [USBController]) -> [String: Any] {
		let model = Machine.shared.modelIdentifier ?? "Hackintosh"
		let usesMergeProperties = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 10, minorVersion: 15, patchVersion: 0))
		var personalities: [String: Any] = [:]

		// One personality per controller, plus one per internal hub.
		let groups = Dictionary(grouping: ports) { "\($0.controllerName)|\($0.controllerLocation)|\($0.hubLocation.map(String.init) ?? "")" }
		for (_, groupPorts) in groups.sorted(by: { $0.key < $1.key }) {
			guard let first = groupPorts.first else { continue }
			let controller = controllers.first { $0.name == first.controllerName && $0.location == first.controllerLocation }
			let isXHCI = controller?.isXHCI ?? first.controllerName.hasPrefix("XH")

			var key = "\(model)-\(first.controllerName)" + (first.isHubPort ? "-internal-hub" : "")
			var suffix = 1
			while personalities[key] != nil {
				suffix += 1
				key = "\(model)-\(first.controllerName)\(first.isHubPort ? "-internal-hub" : "")-\(suffix)"
			}

			var portsDictionary: [String: Any] = [:]
			for port in groupPorts {
				var entry: [String: Any] = [
					"UsbConnector": Int(port.connector),
					"usb-port-type": Int(port.connector),
					"port": Data(littleEndian: port.port),
					"usb-port-number": Data(littleEndian: port.port),
				]
				if let comment = port.comment, !comment.isEmpty {
					entry["Comment"] = comment
				}
				portsDictionary[port.name] = entry
			}

			var mergeProperties: [String: Any] = [
				"port-count": Data(littleEndian: groupPorts.map { $0.port }.max() ?? 0),
				"ports": portsDictionary,
			]
			if isXHCI && !first.isHubPort {
				mergeProperties["kUSBMuxEnabled"] = true
			}

			var personality: [String: Any] = [
				"CFBundleIdentifier": usesMergeProperties ? "com.apple.driver.AppleUSBHostMergeProperties" : "com.apple.driver.AppleUSBMergeNub",
				"IOClass": usesMergeProperties ? "AppleUSBHostMergeProperties" : "AppleUSBMergeNub",
				"IOProbeScore": 5000,
				"IOProviderMergeProperties": mergeProperties,
				"model": model,
			]
			if first.isHubPort {
				personality["IOProviderClass"] = first.hubName ?? "AppleUSB20InternalHub"
				personality["locationID"] = first.hubLocation ?? 0
			} else {
				personality["IOProviderClass"] = controller?.className ?? first.controllerClass ?? (isXHCI ? "AppleUSBXHCIPCI" : "AppleUSBEHCIPCI")
				// Prefer the most specific match available: PCI location, registry path, then ACPI name.
				if let pciDebug = controller?.pciDebug {
					personality["IOParentMatch"] = ["IOPropertyMatch": ["pcidebug": pciDebug]]
				} else if let path = controller?.servicePath {
					personality["IOPathMatch"] = path
				} else {
					personality["IONameMatch"] = first.controllerName
				}
			}
			personalities[key] = personality
		}

		return [
			"CFBundleDevelopmentRegion": "English",
			"CFBundleGetInfoString": "1.0 Created by Hackintool",
			"CFBundleIdentifier": "com.Baker76.USBPorts",
			"CFBundleInfoDictionaryVersion": "6.0",
			"CFBundleName": "USBPorts",
			"CFBundlePackageType": "KEXT",
			"CFBundleShortVersionString": "1.0",
			"CFBundleSignature": "????",
			"CFBundleVersion": "1.0",
			"OSBundleRequired": "Root",
			"IOKitPersonalities": personalities,
		]
	}

	/// Writes USBPorts.kext into `folder`.
	static func writeKext(ports: [USBPort], controllers: [USBController], to folder: URL) throws -> URL {
		let kext = folder.appendingPathComponent("USBPorts.kext")
		try? FileManager.default.removeItem(at: kext)
		let contents = kext.appendingPathComponent("Contents")
		try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
		let data = try PropertyListSerialization.data(fromPropertyList: kextInfoPlist(ports: ports, controllers: controllers), format: .xml, options: 0)
		try data.write(to: contents.appendingPathComponent("Info.plist"))
		return kext
	}

	/// Reads ports back from a USBPorts / USBMap kext.
	static func importKext(at url: URL, controllers: [USBController]) -> [USBPort]? {
		guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else { return nil }
		let personalities = (info["IOKitPersonalities"] ?? info["IOKitPersonalities_x86_64"]) as? [String: [String: Any]] ?? [:]
		var ports: [USBPort] = []
		for (key, personality) in personalities {
			let isHub = key.hasSuffix("-internal-hub") || (personality["IOProviderClass"] as? String)?.contains("Hub") == true
			// "<model>-<controller>[-internal-hub][-n]"
			let parts = key.split(separator: "-")
			guard parts.count >= 2 else { continue }
			let controllerName = (personality["IONameMatch"] as? String) ?? String(parts[1])
			let controller = controllers.first { $0.name == controllerName }
			let merge = personality["IOProviderMergeProperties"] as? [String: Any] ?? [:]
			for (name, value) in merge["ports"] as? [String: [String: Any]] ?? [:] {
				// USBMap keeps disabled ports as "#name".
				guard !name.hasPrefix("#") else { continue }
				let number = IOValue.uint32(value["port"] ?? value["usb-port-number"]) ?? 0
				let connector = UInt8(truncatingIfNeeded: IOValue.uint32(value["UsbConnector"] ?? value["usb-port-type"]) ?? 0)
				ports.append(USBPort(name: name, port: number,
				                     locationID: (controller?.location ?? 0) << 24 | number << 16,
				                     connector: connector, comment: value["Comment"] as? String, isActive: false,
				                     controllerName: controllerName, controllerID: controller?.deviceID ?? 0,
				                     controllerLocation: controller?.location ?? 0, controllerClass: controller?.className,
				                     hubName: isHub ? (personality["IOProviderClass"] as? String ?? "AppleUSB20InternalHub") : nil,
				                     hubLocation: isHub ? IOValue.uint32(personality["locationID"]) : nil,
				                     servicePath: nil, deviceName: nil, deviceSpeed: nil, portClass: nil))
			}
		}
		return ports
	}

	// MARK: SSDTs

	/// SSDT-USBX: USB port power properties (plus a fake EC before macOS 10.15).
	static func ssdtUSBX() -> (name: String, source: String) {
		let catalina = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 10, minorVersion: 15, patchVersion: 0))
		var lines = [
			"DefinitionBlock (\"\", \"SSDT\", 2, \"ACDT\", \"SsdtUSBX\", 0)",
			"{",
			"    Scope (\\_SB)",
			"    {",
			"        If (_OSI (\"Darwin\"))",
			"        {",
			"            Device (USBX)",
			"            {",
			"                Name (_ADR, Zero)  // _ADR: Address",
			"                Method (_DSM, 4, NotSerialized)  // _DSM: Device-Specific Method",
			"                {",
			"                    If ((Arg2 == Zero))",
			"                    {",
			"                        Return (Buffer (One) { 0x03 })",
			"                    }",
			"",
			"                    Return (Package (0x08)",
			"                    {",
			"                        \"kUSBSleepPowerSupply\", 0x13EC,",
			"                        \"kUSBSleepPortCurrentLimit\", 0x0834,",
			"                        \"kUSBWakePowerSupply\", 0x13EC,",
			"                        \"kUSBWakePortCurrentLimit\", 0x0834",
			"                    })",
			"                }",
			"            }",
			"        }",
			"    }",
		]
		if !catalina {
			lines += [
				"",
				"    External (_SB_.PCI0.LPCB, DeviceObj)",
				"",
				"    Scope (\\_SB.PCI0.LPCB)",
				"    {",
				"        Device (EC)",
				"        {",
				"            Name (_HID, \"ACID0001\")  // _HID: Hardware ID",
				"            Method (_STA, 0, NotSerialized)  // _STA: Status",
				"            {",
				"                If (_OSI (\"Darwin\")) { Return (0x0F) }",
				"                Return (Zero)",
				"            }",
				"        }",
				"    }",
			]
		}
		lines.append("}")
		return (catalina ? "SSDT-USBX" : "SSDT-EC-USBX", lines.joined(separator: "\n") + "\n")
	}

	/// SSDT-UIAC for the deprecated USBInjectAll.kext. USBPorts.kext is the replacement.
	static func ssdtUIAC(ports: [USBPort]) -> String {
		var lines = [
			"DefinitionBlock (\"\", \"SSDT\", 2, \"ACDT\", \"_UIAC\", 0)",
			"{",
			"    Device (UIAC)",
			"    {",
			"        Name (_HID, \"UIA00000\")",
			"",
			"        Name (RMCF, Package ()",
			"        {",
		]
		let groups = Dictionary(grouping: ports) { $0.hubName != nil ? "HUB\($0.controllerName.last ?? "1")" : $0.controllerName }
		for (owner, groupPorts) in groups.sorted(by: { $0.key < $1.key }) {
			let portCount = Data(littleEndian: groupPorts.map { $0.port }.max() ?? 0)
			lines += [
				"            \"\(owner)\", Package ()",
				"            {",
				"                \"port-count\", Buffer () { \(portCount.hexString(delimiter: ", ", prefix: "0x")) },",
				"                \"ports\", Package ()",
				"                {",
			]
			for port in groupPorts.sorted(by: { $0.name < $1.name }) {
				let portNumber = Data(littleEndian: port.port).hexString(delimiter: ", ", prefix: "0x")
				// UsbConnector/port for older macOS, plus usb-port-type/usb-port-number,
				// which macOS 26 reads instead.
				lines += [
					"                    \"\(port.name)\", Package ()",
					"                    {",
					"                        \"UsbConnector\", \(port.connector),",
					"                        \"port\", Buffer () { \(portNumber) },",
					"                        \"usb-port-type\", \(port.connector),",
					"                        \"usb-port-number\", Buffer () { \(portNumber) },",
				]
				if let comment = port.comment, !comment.isEmpty {
					lines.append("                        \"Comment\", Buffer () { \"\(comment)\" },")
				}
				lines.append("                    },")
			}
			lines += ["                },", "            },"]
		}
		lines += ["        })", "    }", "}"]
		return lines.joined(separator: "\n") + "\n"
	}

	/// Compiles ACPI source with the bundled iasl next to the .dsl, returning the .aml.
	@discardableResult
	static func compile(_ source: String, named name: String, in folder: URL) -> URL? {
		let dsl = folder.appendingPathComponent(name + ".dsl")
		let aml = folder.appendingPathComponent(name + ".aml")
		guard (try? source.write(to: dsl, atomically: true, encoding: .utf8)) != nil,
		      let iasl = Bundle.main.url(forResource: "iasl", withExtension: nil, subdirectory: "Utilities") else { return nil }
		Shell.run(iasl.path, ["-p", aml.path, dsl.path])
		return FileManager.default.fileExists(atPath: aml.path) ? aml : nil
	}

	// MARK: Renames

	/// Controllers whose ACPI name collides with one macOS reserves, and the rename to use.
	static func neededRenames(_ controllers: [USBController]) -> [(from: String, to: String)] {
		let names = Set(controllers.map { $0.name })
		return reservedControllerNames.filter { names.contains($0.key) }.map { ($0.key, $0.value) }.sorted { $0.from < $1.from }
	}
}
