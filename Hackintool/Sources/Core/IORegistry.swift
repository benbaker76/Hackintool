//
//  IORegistry.swift
//  Hackintool
//
//  A thin, memory-safe wrapper over the I/O Registry.
//

import Foundation
import IOKit

/// An I/O Registry entry. The underlying object is released when this is deallocated.
final class IORegistryEntry {
	enum Plane: String {
		case service = "IOService"
		case deviceTree = "IODeviceTree"
		case power = "IOPower"
		case acpi = "IOACPIPlane"
	}

	let raw: io_registry_entry_t

	/// Takes ownership of a +1 retained registry object.
	init?(owning raw: io_registry_entry_t) {
		guard raw != 0 else { return nil }
		self.raw = raw
	}

	/// Looks up an entry by path, e.g. "IODeviceTree:/options" or "IOService:/".
	convenience init?(path: String) {
		self.init(owning: IORegistryEntryFromPath(kIOMainPortDefaultCompat, path))
	}

	static var root: IORegistryEntry? {
		return IORegistryEntry(owning: IORegistryGetRootEntry(kIOMainPortDefaultCompat))
	}

	deinit {
		IOObjectRelease(raw)
	}

	// MARK: Identity

	var name: String {
		var buffer = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
		guard IORegistryEntryGetName(raw, &buffer) == KERN_SUCCESS else { return "" }
		return String(cString: buffer)
	}

	var className: String {
		var buffer = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
		guard IOObjectGetClass(raw, &buffer) == KERN_SUCCESS else { return "" }
		return String(cString: buffer)
	}

	func conforms(to className: String) -> Bool {
		return IOObjectConformsTo(raw, className) != 0
	}

	var registryID: UInt64 {
		var id: UInt64 = 0
		IORegistryEntryGetRegistryEntryID(raw, &id)
		return id
	}

	func path(in plane: Plane = .service) -> String? {
		var buffer = [CChar](repeating: 0, count: MemoryLayout<io_string_t>.size)
		guard IORegistryEntryGetPath(raw, plane.rawValue, &buffer) == KERN_SUCCESS else { return nil }
		return String(cString: buffer)
	}

	/// The entry's location in its parent ("1d,7" for PCI devices), if it has one.
	func location(in plane: Plane = .service) -> String? {
		var buffer = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
		guard IORegistryEntryGetLocationInPlane(raw, plane.rawValue, &buffer) == KERN_SUCCESS else { return nil }
		return String(cString: buffer)
	}

	// MARK: Properties

	var properties: [String: Any] {
		var dictionary: Unmanaged<CFMutableDictionary>?
		guard IORegistryEntryCreateCFProperties(raw, &dictionary, kCFAllocatorDefault, 0) == KERN_SUCCESS,
		      let properties = dictionary?.takeRetainedValue() as? [String: Any] else { return [:] }
		return properties
	}

	func property(_ key: String) -> Any? {
		return IORegistryEntryCreateCFProperty(raw, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
	}

	/// Searches this entry, then its parents (or children), for a property.
	func searchProperty(_ key: String, in plane: Plane = .service, parents: Bool = true) -> Any? {
		var options = IOOptionBits(kIORegistryIterateRecursively)
		if parents {
			options |= IOOptionBits(kIORegistryIterateParents)
		}
		return IORegistryEntrySearchCFProperty(raw, plane.rawValue, key as CFString, kCFAllocatorDefault, options)
	}

	func string(_ key: String) -> String? {
		return IOValue.string(property(key))
	}

	func uint32(_ key: String) -> UInt32? {
		return IOValue.uint32(property(key))
	}

	func data(_ key: String) -> Data? {
		return property(key) as? Data
	}

	// MARK: Relationships

	func parent(in plane: Plane = .service) -> IORegistryEntry? {
		var parent: io_registry_entry_t = 0
		guard IORegistryEntryGetParentEntry(raw, plane.rawValue, &parent) == KERN_SUCCESS else { return nil }
		return IORegistryEntry(owning: parent)
	}

	func children(in plane: Plane = .service) -> [IORegistryEntry] {
		var iterator: io_iterator_t = 0
		guard IORegistryEntryGetChildIterator(raw, plane.rawValue, &iterator) == KERN_SUCCESS else { return [] }
		return IORegistryEntry.collect(iterator)
	}

	/// All ancestors, nearest first.
	func ancestors(in plane: Plane = .service) -> [IORegistryEntry] {
		var iterator: io_iterator_t = 0
		let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
		guard IORegistryEntryCreateIterator(raw, plane.rawValue, options, &iterator) == KERN_SUCCESS else { return [] }
		return IORegistryEntry.collect(iterator)
	}

	/// All descendants, depth first.
	func descendants(in plane: Plane = .service) -> [IORegistryEntry] {
		var iterator: io_iterator_t = 0
		let options = IOOptionBits(kIORegistryIterateRecursively)
		guard IORegistryEntryCreateIterator(raw, plane.rawValue, options, &iterator) == KERN_SUCCESS else { return [] }
		return IORegistryEntry.collect(iterator)
	}

	/// The nearest ancestor whose class conforms to one of the given classes.
	func ancestor(conformingTo classNames: [String], in plane: Plane = .service) -> IORegistryEntry? {
		return ancestors(in: plane).first { entry in classNames.contains { entry.conforms(to: $0) } }
	}

	/// The first descendant whose class conforms to one of the given classes.
	func descendant(conformingTo classNames: [String], in plane: Plane = .service) -> IORegistryEntry? {
		return descendants(in: plane).first { entry in classNames.contains { entry.conforms(to: $0) } }
	}

	// MARK: Matching

	/// All services whose class conforms to `className`.
	static func services(matching className: String) -> [IORegistryEntry] {
		return services(matching: IOServiceMatching(className))
	}

	/// All services with the given IOName.
	static func services(named name: String) -> [IORegistryEntry] {
		return services(matching: IOServiceNameMatching(name))
	}

	static func services(matching dictionary: CFMutableDictionary?) -> [IORegistryEntry] {
		var iterator: io_iterator_t = 0
		// IOServiceGetMatchingServices consumes the dictionary reference.
		guard let dictionary = dictionary,
		      IOServiceGetMatchingServices(kIOMainPortDefaultCompat, dictionary, &iterator) == KERN_SUCCESS else { return [] }
		return collect(iterator)
	}

	static func firstService(matching className: String) -> IORegistryEntry? {
		return IORegistryEntry(owning: IOServiceGetMatchingService(kIOMainPortDefaultCompat, IOServiceMatching(className)))
	}

	/// Drains and releases an iterator, returning the entries it yields.
	static func collect(_ iterator: io_iterator_t) -> [IORegistryEntry] {
		defer { IOObjectRelease(iterator) }
		var entries: [IORegistryEntry] = []
		while case let next = IOIteratorNext(iterator), next != 0 {
			if let entry = IORegistryEntry(owning: next) {
				entries.append(entry)
			}
		}
		return entries
	}
}

/// kIOMainPortDefault was introduced in macOS 12; the old name works everywhere and both are 0.
let kIOMainPortDefaultCompat: mach_port_t = 0

/// Conversions for the loosely-typed values found in the I/O Registry, where numbers
/// often arrive as little-endian Data and strings as NUL-terminated Data.
enum IOValue {
	static func string(_ value: Any?) -> String? {
		switch value {
		case let string as String:
			return string
		case let data as Data:
			let bytes = data.prefix { $0 != 0 }
			return String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .ascii)
		case let number as NSNumber:
			return number.stringValue
		default:
			return nil
		}
	}

	static func uint32(_ value: Any?) -> UInt32? {
		switch value {
		case let number as NSNumber:
			return number.uint32Value
		case let data as Data where !data.isEmpty:
			return data.prefix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
		case let string as String:
			return UInt32(string)
		default:
			return nil
		}
	}

	static func uint64(_ value: Any?) -> UInt64? {
		switch value {
		case let number as NSNumber:
			return number.uint64Value
		case let data as Data where !data.isEmpty:
			return data.prefix(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
		default:
			return nil
		}
	}

	/// A readable rendering of any registry value, matching the old propertyToString.
	static func display(_ value: Any?) -> String {
		switch value {
		case nil:
			return "???"
		case let data as Data:
			// Printable C strings are shown as text, everything else as hex.
			if let last = data.last, last == 0, data.dropLast().allSatisfy({ $0 >= 0x20 && $0 < 0x7F }), data.count > 1 {
				return string(data) ?? data.hexString()
			}
			return data.hexString()
		case let number as NSNumber:
			return number.stringValue
		case let string as String:
			return string
		default:
			return String(describing: value!)
		}
	}
}
