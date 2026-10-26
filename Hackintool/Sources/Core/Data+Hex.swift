//
//  Data+Hex.swift
//  Hackintool
//
//  Hex, byte and integer conversions used throughout the patching and info code.
//

import Foundation

extension Data {
	/// Formats bytes as hex, e.g. hexString(delimiter: ", ", prefix: "0x") → "0x01, 0xAB".
	/// With `lineBreakEvery`, a newline replaces the delimiter every N bytes.
	func hexString(delimiter: String = "", prefix: String = "", uppercase: Bool = true, lineBreakEvery: Int? = nil) -> String {
		let format = uppercase ? "%02X" : "%02x"
		var result = ""
		result.reserveCapacity(count * (2 + prefix.count + delimiter.count))
		for (index, byte) in enumerated() {
			if index > 0 {
				if let lineBreakEvery = lineBreakEvery, index % lineBreakEvery == 0 {
					result += "\n"
				} else {
					result += delimiter
				}
			}
			result += prefix + String(format: format, byte)
		}
		return result
	}

	/// Xcode-plist style: "<0102 0304>".
	var classicHexString: String {
		var result = "<"
		for (index, byte) in enumerated() {
			if index > 0 && index % 4 == 0 {
				result += " "
			}
			result += String(format: "%02x", byte)
		}
		return result + ">"
	}

	/// Parses hex text, ignoring whitespace, commas, "0x" prefixes and angle brackets.
	init?(hexString: String) {
		let cleaned = hexString
			.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
			.filter { $0.isHexDigit }
		guard cleaned.count % 2 == 0 else { return nil }
		var bytes: [UInt8] = []
		bytes.reserveCapacity(cleaned.count / 2)
		var index = cleaned.startIndex
		while index < cleaned.endIndex {
			let next = cleaned.index(index, offsetBy: 2)
			guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
			bytes.append(byte)
			index = next
		}
		self.init(bytes)
	}

	init(littleEndian value: UInt32) {
		var value = value.littleEndian
		self.init(bytes: &value, count: MemoryLayout<UInt32>.size)
	}

	/// The first four bytes as a little-endian integer (zero padded).
	var littleEndianUInt32: UInt32 {
		return prefix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
	}

	/// Replaces every occurrence of `find` with `replace` (same length), returning the number replaced.
	@discardableResult
	mutating func replaceOccurrences(of find: Data, with replace: Data, limit: Int = .max) -> Int {
		guard !find.isEmpty, find.count == replace.count else { return 0 }
		var replaced = 0
		var searchRange = startIndex..<endIndex
		while replaced < limit, let range = self.range(of: find, in: searchRange) {
			replaceSubrange(range, with: replace)
			replaced += 1
			searchRange = range.upperBound..<endIndex
		}
		return replaced
	}
}

extension UInt32 {
	/// "0x01, 0x02, 0x03, 0x04" in little-endian byte order.
	var byteString: String {
		return Data(littleEndian: self).hexString(delimiter: ", ", prefix: "0x")
	}

	var base64String: String {
		return Data(littleEndian: self).base64EncodedString()
	}

	var hex8: String {
		return String(format: "0x%08X", self)
	}
}

extension String {
	/// Parses "0x1A", "1A" (hex) or plain decimal.
	var hexOrDecimalValue: UInt64? {
		let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.lowercased().hasPrefix("0x") {
			return UInt64(trimmed.dropFirst(2), radix: 16)
		}
		return UInt64(trimmed)
	}
}
