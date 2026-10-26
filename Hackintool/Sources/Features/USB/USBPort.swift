//
//  USBPort.swift
//  Hackintool
//
//  USB controllers and ports from the I/O Registry, and the user's port map.
//
//  The map is the list of ports to keep. Ports are discovered from AppleUSBHostPort
//  services; any port a device has been plugged into during mapping is marked active.
//  The map is saved under the same UserDefaults key and field names as before.
//

import Cocoa

/// USB connector types (ACPI _UPC "UsbConnector" / macOS 26 "usb-port-type").
enum USBConnector: UInt8, CaseIterable {
	case typeA = 0x00
	case miniAB = 0x01
	case expressCard = 0x02
	case usb3StandardA = 0x03
	case usb3StandardB = 0x04
	case usb3MicroB = 0x05
	case usb3MicroAB = 0x06
	case usb3PowerB = 0x07
	/// Type-C with only the USB 2 pair wired.
	case typeCUSB2 = 0x08
	/// Type-C, USB 2 + SuperSpeed through a mux (one port for both orientations).
	case typeCWithSwitch = 0x09
	/// Type-C, USB 2 + SuperSpeed on separate ports per orientation.
	case typeC = 0x0A
	case `internal` = 0xFF

	var name: String {
		switch self {
		case .typeA: return "USB2"
		case .miniAB: return "Mini-AB"
		case .expressCard: return "ExpressCard"
		case .usb3StandardA: return "USB3"
		case .usb3StandardB: return "USB3 Standard-B"
		case .usb3MicroB: return "USB3 Micro-B"
		case .usb3MicroAB: return "USB3 Micro-AB"
		case .usb3PowerB: return "USB3 Power-B"
		case .typeCUSB2: return "TypeC USB2"
		case .typeCWithSwitch: return "TypeC+Sw"
		case .typeC: return "TypeC"
		case .internal: return "Internal"
		}
	}
}

struct USBController {
	/// ACPI name, e.g. "XHC".
	let name: String
	/// The driver class, e.g. "AppleUSBXHCISPT" — the kext's IOProviderClass.
	let className: String
	/// (device << 16) | vendor of the PCI controller.
	let deviceID: UInt32
	/// The top byte of the controller's locationID (its PCI device number on Intel PCHs).
	let location: UInt32
	/// IOService path, for IOPathMatch.
	let servicePath: String
	/// "pcidebug" of the PCI device ("0:20:0"), for IOParentMatch.
	let pciDebug: String?
	let vendorName: String
	let deviceName: String

	var isXHCI: Bool { return className.contains("XHCI") }
	var isEHCI: Bool { return className.contains("EHCI") }

	static func all() -> [USBController] {
		let database = IDDatabase.pci
		return IORegistryEntry.services(matching: "AppleUSBHostController").compactMap { entry in
			guard let pci = entry.ancestor(conformingTo: ["IOPCIDevice"]), let path = entry.path() else { return nil }
			let vendor = pci.uint32("vendor-id") ?? 0
			let device = pci.uint32("device-id") ?? 0
			return USBController(name: entry.name,
			                     className: entry.className,
			                     deviceID: device << 16 | vendor,
			                     location: (entry.uint32("locationID") ?? 0) >> 24,
			                     servicePath: path,
			                     pciDebug: pci.property("pcidebug") as? String,
			                     vendorName: database.vendorName(vendor) ?? "???",
			                     deviceName: database.deviceName(vendorID: vendor, deviceID: device) ?? "???")
		}.sorted { $0.location < $1.location }
	}
}

struct USBPort {
	var name: String
	/// Port number on its controller or hub.
	var port: UInt32
	var locationID: UInt32
	var connector: UInt8
	var comment: String?
	/// Whether a device has been seen on this port while mapping.
	var isActive: Bool

	var controllerName: String
	var controllerID: UInt32
	var controllerLocation: UInt32
	var controllerClass: String?
	var hubName: String?
	var hubLocation: UInt32?

	// Live state, not saved.
	var servicePath: String?
	var deviceName: String?
	var deviceSpeed: Int?
	var portClass: String?

	var isHubPort: Bool { return hubName != nil }

	/// Identifies a physical port across rescans.
	var key: String {
		return "\(controllerName)|\(controllerLocation)|\(hubLocation ?? 0)|\(port)"
	}

	var connectorType: USBConnector? { return USBConnector(rawValue: connector) }

	var speedName: String {
		guard let speed = deviceSpeed else { return "" }
		return ["1.5 Mbps", "12 Mbps", "480 Mbps", "5 Gbps", "10 Gbps", "20 Gbps"].indices.contains(speed)
			? ["1.5 Mbps", "12 Mbps", "480 Mbps", "5 Gbps", "10 Gbps", "20 Gbps"][speed]
			: L("Unknown")
	}
}

// MARK: - Discovery

enum USBDiscovery {
	/// Every port the registry exposes. Hub ports are only included for EHCI controllers'
	/// internal (rate-matching) hubs, as USBMap does; hubs on XHCI need no map.
	static func ports(controllers: [USBController]) -> [USBPort] {
		let controllersByPath = Dictionary(controllers.map { ($0.servicePath, $0) }, uniquingKeysWith: { first, _ in first })
		return IORegistryEntry.services(matching: "AppleUSBHostPort").compactMap { entry in
			guard let controllerEntry = entry.ancestor(conformingTo: ["AppleUSBHostController"]),
			      let controllerPath = controllerEntry.path(),
			      let controller = controllersByPath[controllerPath] else { return nil }

			let properties = entry.properties
			let hub = entry.ancestor(conformingTo: ["AppleUSBHub"])
			if let hub = hub {
				guard controller.isEHCI, hub.className.contains("InternalHub") else { return nil }
			}
			let number = IOValue.uint32(properties["port"]) ?? IOValue.uint32(properties["usb-port-number"]) ?? 0
			let defaultConnector: UInt8 = controller.isXHCI ? USBConnector.usb3StandardA.rawValue : USBConnector.typeA.rawValue
			// Hub ports on older macOS report "portType" instead.
			let connector = (IOValue.uint32(properties["UsbConnector"]) ?? IOValue.uint32(properties["usb-port-type"]) ?? IOValue.uint32(properties["portType"])).map { UInt8(truncatingIfNeeded: $0) } ?? defaultConnector

			return USBPort(name: entry.name,
			               port: number,
			               locationID: IOValue.uint32(properties["locationID"]) ?? 0,
			               connector: connector,
			               comment: properties["Comment"] as? String,
			               isActive: false,
			               controllerName: controller.name,
			               controllerID: controller.deviceID,
			               controllerLocation: controller.location,
			               controllerClass: controller.className,
			               hubName: hub?.className,
			               hubLocation: hub.flatMap { IOValue.uint32($0.property("locationID")) },
			               servicePath: entry.path(),
			               deviceName: nil,
			               deviceSpeed: nil,
			               portClass: entry.className)
		}
	}

	/// Devices currently attached, keyed by the IOService path of the port they're on.
	static func attachedDevices() -> [String: (name: String, speed: Int?)] {
		var devices: [String: (name: String, speed: Int?)] = [:]
		for device in IORegistryEntry.services(matching: "IOUSBHostDevice") {
			guard let port = device.ancestor(conformingTo: ["AppleUSBHostPort"]), let path = port.path() else { continue }
			let properties = device.properties
			let name = properties["USB Product Name"] as? String ?? properties["kUSBProductString"] as? String ?? device.name
			let speed = IOValue.uint32(properties["Device Speed"] ?? properties["USBSpeed"]).map { Int($0) }
			devices[path] = (name, speed)
		}
		return devices
	}
}

// MARK: - The map

final class USBPortMap {
	private(set) var ports: [USBPort] = []
	private(set) var controllers: [USBController] = []
	var onChange: (() -> Void)?

	private static let defaultsKey = "USBPorts"
	private var watcher: IOServiceWatcher?
	private let debouncer = Debouncer(delay: 0.5)

	init() {
		ports = USBPortMap.load()
	}

	/// Watches for devices being plugged in, marking their ports active.
	func startWatching() {
		watcher = IOServiceWatcher(className: "IOUSBHostDevice") { [weak self] _ in
			self?.debouncer.schedule { self?.refreshDevices() }
		}
	}

	/// Re-reads controllers and ports, adding newly seen ports and keeping user edits to known ones.
	func refresh() {
		controllers = USBController.all()
		let discovered = USBDiscovery.ports(controllers: controllers)
		for var port in discovered {
			if let index = ports.firstIndex(where: { $0.key == port.key }) {
				// Keep the user's name, connector and comment; refresh what the registry knows.
				ports[index].servicePath = port.servicePath
				ports[index].portClass = port.portClass
				ports[index].locationID = port.locationID
				ports[index].controllerID = port.controllerID
				ports[index].controllerClass = port.controllerClass
			} else {
				port.name = USBPortNaming.name(for: port, existing: ports)
				ports.append(port)
			}
		}
		sort()
		refreshDevices()
	}

	/// Updates which ports have devices on them now.
	func refreshDevices() {
		let devices = USBDiscovery.attachedDevices()
		for index in ports.indices {
			guard let path = ports[index].servicePath, let device = devices[path] else {
				ports[index].deviceName = nil
				ports[index].deviceSpeed = nil
				continue
			}
			ports[index].deviceName = device.name
			ports[index].deviceSpeed = device.speed
			ports[index].isActive = true
		}
		save()
		onChange?()
	}

	func update(_ port: USBPort, _ change: (inout USBPort) -> Void) {
		guard let index = ports.firstIndex(where: { $0.key == port.key }) else { return }
		change(&ports[index])
		save()
		onChange?()
	}

	func remove(_ removed: [USBPort]) {
		let keys = Set(removed.map { $0.key })
		ports.removeAll { keys.contains($0.key) }
		save()
		onChange?()
	}

	func removeAll() {
		ports.removeAll()
		save()
		onChange?()
	}

	/// Removes ports that never had a device plugged in during mapping.
	func removeInactive() {
		ports.removeAll { !$0.isActive }
		save()
		onChange?()
	}

	/// Adds ports from an imported USBPorts kext, replacing the map.
	func replace(with imported: [USBPort]) {
		ports = imported
		refresh()
	}

	/// Adds every port USBInjectAll knows for the Intel controllers present (for mapping
	/// ports hidden by the 15-port limit).
	func injectTemplatePorts() {
		for port in USBInjectAllTemplate.ports(for: controllers) where !ports.contains(where: { $0.key == port.key }) {
			ports.append(port)
		}
		sort()
		save()
		onChange?()
	}

	/// Ports per personality (controller or hub), for the 15-port limit.
	func portCounts() -> [(owner: String, count: Int)] {
		var counts: [String: Int] = [:]
		for port in ports {
			counts[port.hubName.map { "\(port.controllerName) \($0)" } ?? port.controllerName, default: 0] += 1
		}
		return counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
	}

	private func sort() {
		ports.sort { a, b in
			if a.controllerLocation != b.controllerLocation { return a.controllerLocation < b.controllerLocation }
			if (a.hubLocation ?? 0) != (b.hubLocation ?? 0) { return (a.hubLocation ?? 0) < (b.hubLocation ?? 0) }
			return a.port < b.port
		}
	}

	// MARK: Persistence (same keys as the Objective-C app)

	private func save() {
		let array: [[String: Any]] = ports.map { port in
			var dictionary: [String: Any] = [
				"name": port.name,
				"port": Data(littleEndian: port.port),
				"locationID": port.locationID,
				"UsbConnector": Int(port.connector),
				"UsbController": port.controllerName,
				"UsbControllerID": port.controllerID,
				"UsbControllerLocationID": port.controllerLocation,
				"IsActive": port.isActive,
			]
			dictionary["Comment"] = port.comment
			dictionary["UsbControllerIOClass"] = port.controllerClass
			dictionary["HubName"] = port.hubName
			dictionary["HubLocation"] = port.hubLocation
			return dictionary
		}
		UserDefaults.standard.set(array, forKey: USBPortMap.defaultsKey)
	}

	private static func load() -> [USBPort] {
		let array = UserDefaults.standard.array(forKey: defaultsKey) as? [[String: Any]] ?? []
		return array.compactMap { dictionary in
			guard let controller = dictionary["UsbController"] as? String else { return nil }
			return USBPort(name: dictionary["name"] as? String ?? "??",
			               port: IOValue.uint32(dictionary["port"]) ?? 0,
			               locationID: IOValue.uint32(dictionary["locationID"]) ?? 0,
			               connector: UInt8(truncatingIfNeeded: IOValue.uint32(dictionary["UsbConnector"] ?? dictionary["portType"]) ?? 0),
			               comment: dictionary["Comment"] as? String,
			               isActive: dictionary["IsActive"] as? Bool ?? false,
			               controllerName: controller,
			               controllerID: IOValue.uint32(dictionary["UsbControllerID"]) ?? 0,
			               controllerLocation: IOValue.uint32(dictionary["UsbControllerLocationID"]) ?? 0,
			               controllerClass: dictionary["UsbControllerIOClass"] as? String,
			               hubName: dictionary["HubName"] as? String,
			               hubLocation: IOValue.uint32(dictionary["HubLocation"]),
			               servicePath: nil, deviceName: nil, deviceSpeed: nil, portClass: nil)
		}
	}
}

// MARK: - Naming

enum USBPortNaming {
	/// A name for a newly discovered port: USBInjectAll's name for Intel controllers,
	/// otherwise HSxx/SSxx (XHCI), PRxx (EHCI) or HPxx (hub) by port number.
	static func name(for port: USBPort, existing: [USBPort]) -> String {
		if port.hubName == nil, let name = USBInjectAllTemplate.portName(controllerID: port.controllerID, port: port.port) {
			return name
		}
		let prefix: String
		if port.isHubPort {
			prefix = "HP"
		} else if port.portClass?.contains("30XHCI") == true {
			prefix = "SS"
		} else if port.portClass?.contains("XHCI") == true {
			prefix = "HS"
		} else if port.portClass?.contains("EHCI") == true {
			prefix = "PR"
		} else {
			prefix = "UK"
		}
		var name = String(format: "%@%02d", prefix, port.port)
		// Ports on different controllers can share a number; keep names unique.
		var suffix = 1
		while existing.contains(where: { $0.name == name && $0.controllerName == port.controllerName && $0.hubLocation == port.hubLocation }) {
			name = String(format: "%@%02d", prefix, Int(port.port) + 100 * suffix)
			suffix += 1
		}
		return name
	}
}

/// Port layouts from USBInjectAll's Info.plist (Resources/USB/USBInjectAll-Info.plist).
enum USBInjectAllTemplate {
	private static let configuration: [String: [String: Any]] = {
		guard let plist = BundledData.plist("USBInjectAll-Info", in: "USB") as? [String: Any],
		      let personalities = plist["IOKitPersonalities"] as? [String: Any],
		      let data = personalities["ConfigurationData"] as? [String: Any],
		      let configuration = data["Configuration"] as? [String: [String: Any]] else { return [:] }
		return configuration
	}()

	/// "8086_a2af", then "8086_a2xx", then "8086_axxx".
	private static func keys(for controllerID: UInt32) -> [String] {
		let vendor = controllerID & 0xFFFF
		let device = controllerID >> 16
		return [
			String(format: "%04x_%04x", vendor, device),
			String(format: "%04x_%02xxx", vendor, (device & 0xFF00) >> 8),
			String(format: "%04x_%01xxxx", vendor, (device & 0xF000) >> 12),
		]
	}

	private static func templatePorts(controllerID: UInt32) -> [String: [String: Any]]? {
		guard controllerID & 0xFFFF == PCIVendor.intel else { return nil }
		for key in keys(for: controllerID) {
			if let ports = configuration[key]?["ports"] as? [String: [String: Any]] {
				return ports
			}
		}
		return nil
	}

	static func portName(controllerID: UInt32, port: UInt32) -> String? {
		return templatePorts(controllerID: controllerID)?.first { IOValue.uint32($0.value["port"]) == port }?.key
	}

	static func ports(for controllers: [USBController]) -> [USBPort] {
		var ports: [USBPort] = []
		for controller in controllers {
			guard let template = templatePorts(controllerID: controller.deviceID) else { continue }
			for (name, entry) in template {
				let number = IOValue.uint32(entry["port"]) ?? 0
				ports.append(USBPort(name: name, port: number, locationID: controller.location << 24 | number << 16,
				                     connector: UInt8(truncatingIfNeeded: IOValue.uint32(entry["UsbConnector"]) ?? 3),
				                     comment: nil, isActive: false,
				                     controllerName: controller.name, controllerID: controller.deviceID,
				                     controllerLocation: controller.location, controllerClass: controller.className,
				                     hubName: nil, hubLocation: nil,
				                     servicePath: nil, deviceName: nil, deviceSpeed: nil, portClass: nil))
			}
		}
		return ports
	}
}
