//
//  CalculatorViewController.swift
//  Hackintool
//
//  Calc section: converts byte sequences between hex, reversed hex, Base64 and ASCII,
//  and numbers between hex, decimal, octal and binary. Editing any field updates the rest.
//

import Cocoa

final class CalculatorViewController: NSViewController, NSTextFieldDelegate {
	private let hexSequence = Form.textField(monospaced: true, placeholder: "e.g. 4C 69 6C 75")
	private let reversedHexSequence = Form.textField(monospaced: true)
	private let base64Sequence = Form.textField(monospaced: true)
	private let asciiSequence = Form.textField(monospaced: true)

	private let hexValue = Form.textField(monospaced: true)
	private let decimalValue = Form.textField(monospaced: true)
	private let octalValue = Form.textField(monospaced: true)
	private let binaryValue = Form.textField(monospaced: true)

	override func loadView() {
		[hexSequence, reversedHexSequence, base64Sequence, asciiSequence, hexValue, decimalValue, octalValue, binaryValue].forEach {
			$0.delegate = self
		}
		reversedHexSequence.isEditable = false

		let sequences = Form.box("Byte Sequence", content: Form.grid([
			("Hex", hexSequence),
			("Hex (Reversed)", reversedHexSequence),
			("Base64", base64Sequence),
			("ASCII", asciiSequence),
		]))
		let values = Form.box("Value", content: Form.grid([
			("Hex", hexValue),
			("Decimal", decimalValue),
			("Octal", octalValue),
			("Binary", binaryValue),
		]))
		view = Form.scrollingStack([sequences, values])
	}

	func controlTextDidChange(_ notification: Notification) {
		guard let field = notification.object as? NSTextField else { return }
		switch field {
		case hexSequence:
			showSequence(Data(hexString: field.stringValue) ?? Data(), except: field)
		case base64Sequence:
			showSequence(Data(base64Encoded: field.stringValue, options: .ignoreUnknownCharacters) ?? Data(), except: field)
		case asciiSequence:
			showSequence(field.stringValue.data(using: .ascii, allowLossyConversion: true) ?? Data(), except: field)
		case hexValue:
			showValue(UInt64(field.stringValue.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive), radix: 16) ?? 0, except: field)
		case decimalValue:
			showValue(UInt64(field.stringValue) ?? 0, except: field)
		case octalValue:
			showValue(UInt64(field.stringValue, radix: 8) ?? 0, except: field)
		case binaryValue:
			showValue(UInt64(field.stringValue.filter { $0 == "0" || $0 == "1" }, radix: 2) ?? 0, except: field)
		default:
			break
		}
	}

	private func showSequence(_ data: Data, except source: NSTextField) {
		let updates: [(NSTextField, String)] = [
			(hexSequence, data.hexString(delimiter: " ")),
			(reversedHexSequence, Data(data.reversed()).hexString(delimiter: " ")),
			(base64Sequence, data.base64EncodedString()),
			(asciiSequence, String(decoding: data.map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self)),
		]
		updates.filter { $0.0 !== source }.forEach { $0.0.stringValue = $0.1 }
	}

	private func showValue(_ value: UInt64, except source: NSTextField) {
		let updates: [(NSTextField, String)] = [
			(hexValue, String(value, radix: 16, uppercase: true)),
			(decimalValue, String(value)),
			(octalValue, String(value, radix: 8)),
			(binaryValue, String(value, radix: 2)),
		]
		updates.filter { $0.0 !== source }.forEach { $0.0.stringValue = $0.1 }
	}
}
