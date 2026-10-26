//
//  NVRAM.swift
//  Hackintool
//
//  Reading NVRAM variables from IODeviceTree:/options and writing them with nvram(8).
//

import Foundation

struct NVRAMVariable {
	enum Value {
		case string(String)
		case number(NSNumber)
		case data(Data)
	}

	let name: String
	let value: Value

	/// A one-line summary for the table.
	var summary: String {
		switch value {
		case .string(let string): return string
		case .number(let number): return number.stringValue
		case .data(let data):
			// Many binary variables are really text (auto-boot is "true").
			let text = data.last == 0 ? data.dropLast() : data
			if !text.isEmpty, text.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }), let string = String(data: text, encoding: .ascii) {
				return "\"" + string + "\""
			}
			return data.classicHexString
		}
	}

	/// The text shown in the editor: XML pretty-printed, or hex bytes.
	var editableText: String {
		switch value {
		case .string(let string): return string
		case .number(let number): return number.stringValue
		case .data(let data):
			if let xml = NVRAM.formattedXML(data) {
				return xml
			}
			return data.hexString(delimiter: " ", prefix: "0x", lineBreakEvery: 8)
		}
	}

	var typeName: String {
		switch value {
		case .string: return L("String")
		case .number: return L("Number")
		case .data: return L("Data")
		}
	}
}

enum NVRAM {
	static func variables() -> [NVRAMVariable] {
		guard let options = IORegistryEntry(path: "IODeviceTree:/options") else { return [] }
		return options.properties.compactMap { name, value -> NVRAMVariable? in
			switch value {
			case let string as String: return NVRAMVariable(name: name, value: .string(string))
			case let number as NSNumber: return NVRAMVariable(name: name, value: .number(number))
			case let data as Data: return NVRAMVariable(name: name, value: .data(data))
			default: return nil
			}
		}.sorted { $0.name < $1.name }
	}

	/// The value of one variable as printed by nvram(8), or nil if it isn't set.
	static func value(of name: String) -> String? {
		guard let output = Shell.output("/usr/sbin/nvram", [name]), let tab = output.firstIndex(of: "\t") else { return nil }
		return output[output.index(after: tab)...].trimmingCharacters(in: .newlines)
	}

	/// Sets a string variable.
	@discardableResult
	static func set(_ name: String, string: String) -> Bool {
		return Privileges.shared.run("/usr/sbin/nvram", ["\(name)=\(string)"]) != nil
	}

	/// Sets a binary variable, percent-encoding each byte as nvram(8) expects.
	@discardableResult
	static func set(_ name: String, data: Data) -> Bool {
		return set(name, string: data.hexString(prefix: "%"))
	}

	@discardableResult
	static func delete(_ name: String) -> Bool {
		return Privileges.shared.run("/usr/sbin/nvram", ["-d", name]) != nil
	}

	/// Writes edited text back, interpreting it the way the variable is stored.
	@discardableResult
	static func save(_ text: String, to variable: NVRAMVariable) -> Bool {
		switch variable.value {
		case .string, .number:
			return set(variable.name, string: text)
		case .data:
			// XML (e.g. efi-boot-device) is stored compact; anything else is hex bytes.
			if let xml = compactXML(text), let data = xml.data(using: .ascii) {
				return set(variable.name, data: data)
			}
			guard let data = Data(hexString: text) else { return false }
			return set(variable.name, data: data)
		}
	}

	/// Pretty-prints data that holds an XML document (minus any trailing NUL).
	static func formattedXML(_ data: Data) -> String? {
		let bytes = data.prefix { $0 != 0 }
		guard bytes.first == UInt8(ascii: "<"), let text = String(data: bytes, encoding: .ascii),
		      let document = try? XMLDocument(xmlString: "<root>\(text)</root>", options: []) else { return nil }
		let children = document.rootElement()?.children ?? []
		return children.map { $0.xmlString(options: [.nodePrettyPrint]) }.joined(separator: "\n")
	}

	/// Re-serialises XML text without whitespace between elements.
	static func compactXML(_ text: String) -> String? {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.hasPrefix("<"), let document = try? XMLDocument(xmlString: "<root>\(trimmed)</root>", options: [.nodePreserveWhitespace]) else { return nil }
		stripWhitespace(document.rootElement())
		return (document.rootElement()?.children ?? []).map { $0.xmlString(options: [.nodeCompactEmptyElement]) }.joined()
	}

	private static func stripWhitespace(_ node: XMLNode?) {
		guard let element = node as? XMLElement else { return }
		for child in element.children ?? [] {
			if child.kind == .text, child.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true, (element.children?.count ?? 0) > 1 {
				child.detach()
			} else {
				stripWhitespace(child)
			}
		}
	}
}
