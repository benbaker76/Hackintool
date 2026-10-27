//
//  PropertyListNode.swift
//  Hackintool
//
//  One entry in a property list tree: a key, a type, and a value or ordered children.
//
//  Swift port of LNPropertyListEditor by Leo Natan (https://github.com/LeoNatan/LNPropertyListEditor).
//  Copyright © 2018-2021 Leo Natan. Released under the MIT License.
//

import Cocoa

final class PropertyListNode: NSObject, NSCoding {
	enum Kind: Int {
		case unknown, array, dictionary, boolean, date, data, number, string

		/// The types in the order the type menus list them; nil marks a separator.
		static let menuOrder: [Kind?] = [.array, .dictionary, nil, .boolean, .data, .date, .number, .string]

		var name: String {
			switch self {
			case .unknown: return ""
			case .array: return "Array"
			case .dictionary: return "Dictionary"
			case .boolean: return "Boolean"
			case .date: return "Date"
			case .data: return "Data"
			case .number: return "Number"
			case .string: return "String"
			}
		}

		var isContainer: Bool {
			return self == .array || self == .dictionary
		}

		/// The value a node gets when it's converted to this type.
		var defaultValue: Any? {
			switch self {
			case .unknown, .array, .dictionary: return nil
			case .boolean: return false
			case .date: return Date()
			case .data: return Data()
			case .number: return 0
			case .string: return ""
			}
		}

		init(of object: Any) {
			switch object {
			case is NSArray: self = .array
			case is NSDictionary: self = .dictionary
			case is NSString: self = .string
			case is NSDate: self = .date
			case is NSData: self = .data
			case let number as NSNumber: self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .boolean : .number
			default: self = .unknown
			}
		}
	}

	@objc var key: String?
	var type: Kind
	@objc var value: Any?
	/// Ordered children of an array or dictionary; nil for other types.
	var children: [PropertyListNode]?
	weak var parent: PropertyListNode?

	/// The data transformer's display value, cached while the row is shown.
	var cachedDisplayValue: Any?

	/// The type the row shows: the display value's when transformed, otherwise the node's own.
	var appropriateType: Kind {
		return cachedDisplayValue.map { Kind(of: $0) } ?? type
	}

	init(key: String? = nil, type: Kind, value: Any? = nil, children: [PropertyListNode]? = nil) {
		self.key = key
		self.type = type
		self.value = value
		self.children = children
		super.init()
		children?.forEach { $0.parent = self }
	}

	/// A tree built from a property list object (NSDictionary, NSArray, NSString, …).
	/// Dictionary keys come out in no particular order; `init(xmlData:)` keeps the file's order.
	convenience init?(propertyList object: Any) {
		self.init(type: .unknown)
		guard setObject(object) else { return nil }
	}

	/// Replaces this node's type and value (or children) with the object's.
	@discardableResult
	func setObject(_ object: Any) -> Bool {
		let kind = Kind(of: object)
		switch kind {
		case .unknown:
			return false
		case .dictionary:
			type = .dictionary
			value = nil
			let dictionary = object as? [String: Any] ?? [:]
			children = dictionary.compactMap { key, value in
				let child = PropertyListNode(propertyList: value)
				child?.key = key
				return child
			}
		case .array:
			type = .array
			value = nil
			children = (object as? [Any] ?? []).compactMap { PropertyListNode(propertyList: $0) }
		default:
			type = kind
			value = object
			children = nil
		}
		children?.forEach { $0.parent = self }
		return true
	}

	/// The node as a property list object. Dictionaries lose their key order.
	var propertyListObject: Any? {
		switch type {
		case .dictionary:
			var dictionary: [String: Any] = [:]
			for child in children ?? [] {
				dictionary[child.key ?? ""] = child.propertyListObject
			}
			return dictionary
		case .array:
			return (children ?? []).compactMap { $0.propertyListObject }
		default:
			return value
		}
	}

	func childNode(containingDescendant descendant: PropertyListNode) -> PropertyListNode? {
		var node: PropertyListNode? = descendant
		while let current = node, !(children ?? []).contains(current) {
			node = current.parent
		}
		return node
	}

	func childNode(forKey key: String) -> PropertyListNode? {
		return children?.first { $0.key == key }
	}

	/// A deep copy, detached from any parent.
	func deepCopy() -> PropertyListNode {
		return PropertyListNode(key: key, type: type, value: value, children: children?.map { $0.deepCopy() })
	}

	override var description: String {
		var text = "<PropertyListNode"
		if let key = key {
			text += " key: “\(key)”"
		}
		text += " type: “\(type.name)”"
		if type.isContainer {
			text += " children: “\(children?.count ?? 0) items”"
		} else {
			text += " value: “\(value.map { String(describing: $0) } ?? "nil")”"
		}
		return text + ">"
	}

	// MARK: Display strings

	/// The key column: the key, or "Item N" inside an array.
	var displayKey: String {
		if parent?.type == .array, let index = parent?.children?.firstIndex(of: self) {
			return String(format: L("Item %d"), index)
		}
		return key ?? ""
	}

	/// The value column's text.
	var displayValue: String {
		let shown = cachedDisplayValue ?? value
		switch appropriateType {
		case .unknown, .date:
			return ""
		case .array, .dictionary:
			let count: Int
			switch cachedDisplayValue {
			case let array as [Any]: count = array.count
			case let dictionary as [String: Any]: count = dictionary.count
			default: count = children?.count ?? 0
			}
			return String(format: count == 1 ? L("(%d item)") : L("(%d items)"), count)
		case .boolean:
			return (shown as? Bool ?? false) ? "YES" : "NO"
		case .data:
			return (shown as? Data)?.classicHexString ?? ""
		case .number:
			return (shown as? NSNumber).map(PropertyListNode.string(from:)) ?? ""
		case .string:
			return shown as? String ?? ""
		}
	}

	static func string(from number: NSNumber) -> String {
		return CFNumberIsFloatType(number) ? "\(number.doubleValue)" : "\(number.int64Value)"
	}

	/// Parses what was typed into a value cell; nil when it isn't valid for the type.
	static func value(from string: String, type: Kind) -> Any? {
		let trimmed = string.trimmingCharacters(in: .whitespaces)
		switch type {
		case .boolean:
			switch trimmed.lowercased() {
			case "yes", "true", "1": return true
			case "no", "false", "0": return false
			default: return nil
			}
		case .number:
			if trimmed.lowercased().hasPrefix("0x") || trimmed.lowercased().hasPrefix("-0x") {
				let negative = trimmed.hasPrefix("-")
				guard let magnitude = Int64(trimmed.dropFirst(negative ? 3 : 2), radix: 16) else { return nil }
				return NSNumber(value: negative ? -magnitude : magnitude)
			}
			if let integer = Int64(trimmed) {
				return NSNumber(value: integer)
			}
			return Double(trimmed).map { NSNumber(value: $0) }
		case .data:
			return Data(hexString: trimmed)
		case .string:
			return string
		case .unknown, .array, .dictionary, .date:
			return nil
		}
	}

	/// Sorting by the Value column compares what the column shows.
	@objc var sortValue: String {
		switch type {
		case .date: return (value as? Date).map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? ""
		case .data: return "<Data>"
		default: return displayValue
		}
	}

	@objc var sortKey: String {
		return key ?? ""
	}

	@objc var sortType: Int {
		return type.rawValue
	}

	// MARK: NSCoding (pasteboard)

	func encode(with coder: NSCoder) {
		coder.encode(key, forKey: "key")
		coder.encode(type.rawValue, forKey: "type")
		coder.encode(value, forKey: "value")
		coder.encode(children, forKey: "children")
	}

	init?(coder: NSCoder) {
		key = coder.decodeObject(forKey: "key") as? String
		type = Kind(rawValue: coder.decodeInteger(forKey: "type")) ?? .unknown
		value = coder.decodeObject(forKey: "value")
		children = coder.decodeObject(forKey: "children") as? [PropertyListNode]
		super.init()
		children?.forEach { $0.parent = self }
	}
}

// MARK: - XML in the file's order

extension PropertyListNode {
	/// Parses an XML property list keeping dictionary keys in the order they're written.
	/// Falls back to PropertyListSerialization (keys sorted) for binary or OpenStep plists.
	convenience init?(xmlData data: Data) {
		if let document = try? XMLDocument(data: data, options: []),
		   let root = document.rootElement() {
			let element = root.name == "plist" ? root.children?.compactMap({ $0 as? XMLElement }).first : root
			if let element = element, let node = PropertyListNode.parse(element) {
				self.init(type: node.type, value: node.value, children: node.children)
				return
			}
		}
		guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
		self.init(type: .unknown)
		setObject(object)
		sortDictionaries()
	}

	convenience init?(xmlString: String) {
		guard let data = xmlString.data(using: .utf8) else { return nil }
		self.init(xmlData: data)
	}

	private static func parse(_ element: XMLElement) -> PropertyListNode? {
		let text = element.stringValue ?? ""
		switch element.name {
		case "dict":
			var children: [PropertyListNode] = []
			var key: String?
			for child in element.children?.compactMap({ $0 as? XMLElement }) ?? [] {
				if child.name == "key" {
					key = child.stringValue ?? ""
				} else if let node = parse(child) {
					node.key = key ?? ""
					key = nil
					children.append(node)
				}
			}
			return PropertyListNode(type: .dictionary, children: children)
		case "array":
			return PropertyListNode(type: .array, children: element.children?.compactMap { ($0 as? XMLElement).flatMap(parse) } ?? [])
		case "string":
			return PropertyListNode(type: .string, value: text)
		case "integer":
			let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
			let number = Int64(trimmed).map { NSNumber(value: $0) } ?? UInt64(trimmed).map { NSNumber(value: $0) }
			return number.map { PropertyListNode(type: .number, value: $0) }
		case "real":
			return Double(text.trimmingCharacters(in: .whitespacesAndNewlines)).map { PropertyListNode(type: .number, value: NSNumber(value: $0)) }
		case "true", "false":
			return PropertyListNode(type: .boolean, value: element.name == "true")
		case "data":
			let base64 = text.components(separatedBy: .whitespacesAndNewlines).joined()
			return Data(base64Encoded: base64).map { PropertyListNode(type: .data, value: $0) }
		case "date":
			return ISO8601DateFormatter().date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)).map { PropertyListNode(type: .date, value: $0) }
		default:
			return nil
		}
	}

	private func sortDictionaries() {
		if type == .dictionary {
			children?.sort { ($0.key ?? "").localizedStandardCompare($1.key ?? "") == .orderedAscending }
		}
		children?.forEach { $0.sortDictionaries() }
	}

	/// The node as an XML property list, keeping the tree's order.
	var xmlString: String {
		var lines = [
			"<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
			"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
			"<plist version=\"1.0\">",
		]
		appendXML(to: &lines, indent: "")
		lines.append("</plist>")
		return lines.joined(separator: "\n") + "\n"
	}

	private func appendXML(to lines: inout [String], indent: String) {
		func escaped(_ string: String) -> String {
			return string.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
		}
		switch type {
		case .dictionary:
			guard let children = children, !children.isEmpty else {
				lines.append(indent + "<dict/>")
				return
			}
			lines.append(indent + "<dict>")
			for child in children {
				lines.append(indent + "\t<key>\(escaped(child.key ?? ""))</key>")
				child.appendXML(to: &lines, indent: indent + "\t")
			}
			lines.append(indent + "</dict>")
		case .array:
			guard let children = children, !children.isEmpty else {
				lines.append(indent + "<array/>")
				return
			}
			lines.append(indent + "<array>")
			children.forEach { $0.appendXML(to: &lines, indent: indent + "\t") }
			lines.append(indent + "</array>")
		case .boolean:
			lines.append(indent + ((value as? Bool ?? false) ? "<true/>" : "<false/>"))
		case .number:
			let number = value as? NSNumber ?? 0
			lines.append(indent + (CFNumberIsFloatType(number) ? "<real>\(number.doubleValue)</real>" : "<integer>\(number.int64Value)</integer>"))
		case .string:
			lines.append(indent + "<string>\(escaped(value as? String ?? ""))</string>")
		case .data:
			lines.append(indent + "<data>\((value as? Data ?? Data()).base64EncodedString())</data>")
		case .date:
			let formatter = ISO8601DateFormatter()
			lines.append(indent + "<date>\(formatter.string(from: value as? Date ?? Date()))</date>")
		case .unknown:
			break
		}
	}
}

// MARK: - Pasteboard

extension NSPasteboard.PasteboardType {
	static let propertyListNode = NSPasteboard.PasteboardType("com.LeoNatan.LNPropertyList.node")
	/// What Xcode's plist editor puts on the pasteboard, so keys can be copied between the two.
	static let xcodePlistKey = NSPasteboard.PasteboardType("com.apple.xcode.plist.key")
}

extension PropertyListNode {
	/// Nodes being dragged or copied in this process, so a drop moves the original rather than a copy.
	private static let pasteboardNodes = NSMapTable<NSString, PropertyListNode>.strongToWeakObjects()

	static func clearPasteboardMapping() {
		pasteboardNodes.removeAllObjects()
	}

	/// The node's pasteboard representations: our own, Xcode's key, and the value as XML text.
	var pasteboardWriter: NSPasteboardWriting {
		let item = NSPasteboardItem()
		let identifier = UUID().uuidString
		PropertyListNode.pasteboardNodes.setObject(self, forKey: identifier as NSString)
		if let archive = try? NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: false),
		   let data = try? PropertyListSerialization.data(fromPropertyList: ["UDID": identifier, "data": archive], format: .xml, options: 0) {
			item.setData(data, forType: .propertyListNode)
		}
		if let key = key, let data = key.data(using: .utf8) {
			item.setData(data, forType: .xcodePlistKey)
		}
		// Without a key there's nothing to wrap the value in, so it goes up as a bare plist.
		item.setString(xmlString, forType: .string)
		return item
	}

	/// The node on the pasteboard: ours (the original, if it's still around) or one copied from Xcode.
	static func node(from pasteboard: NSPasteboard) -> PropertyListNode? {
		if let data = pasteboard.data(forType: .propertyListNode),
		   let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
			if let identifier = info["UDID"] as? String, let node = pasteboardNodes.object(forKey: identifier as NSString) {
				return node
			}
			if let archive = info["data"] as? Data,
			   let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archive) {
				unarchiver.requiresSecureCoding = false
				unarchiver.setClass(PropertyListNode.self, forClassName: NSStringFromClass(PropertyListNode.self))
				return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? PropertyListNode
			}
		}
		if let data = pasteboard.data(forType: .xcodePlistKey) {
			let node = PropertyListNode(type: .string, value: "")
			node.key = String(data: data, encoding: .utf8)
			if let text = pasteboard.data(forType: .string), let parsed = PropertyListNode(xmlData: text) {
				node.type = parsed.type
				node.value = parsed.value
				node.children = parsed.children
				node.children?.forEach { $0.parent = node }
			}
			return node
		}
		return nil
	}

	static func pasteboardHasNode(_ pasteboard: NSPasteboard) -> Bool {
		return pasteboard.availableType(from: [.propertyListNode, .xcodePlistKey]) != nil
	}
}
