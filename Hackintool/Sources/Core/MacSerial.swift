//
//  MacSerial.swift
//  Hackintool
//
//  Decodes and generates Mac serial numbers using acidanthera's macserial (C).
//

import Foundation

enum MacSerial {
	struct Decoded {
		var country: String?
		var year: String
		/// Date range of the manufacturing week, e.g. "03.05.2019-03.11.2019".
		var week: String?
		var line: String
		var model: String
		var modelIdentifier: String
		var isValid: Bool
	}

	struct Generated {
		let serialNumber: String
		let boardSerialNumber: String
		let smUUID: String
	}

	/// Model identifiers macserial can generate serials for ("iMac19,1", ...).
	static let modelIdentifiers: [String] = (0..<macserial_model_count()).compactMap { index in
		macserial_product_name(index).map { String(cString: $0) }
	}

	/// Decodes a legacy (11 or 12 character) serial; nil if it isn't one, e.g. on Apple Silicon Macs.
	static func decode(_ serialNumber: String) -> Decoded? {
		// macserial only understands the pre-2021 formats; newer serials are 10 random characters.
		guard serialNumber.count == 11 || serialNumber.count == 12 else { return nil }
		var info = macserial_empty_info()
		_ = serialNumber.withCString { get_serial_info($0, &info, false) }

		let country = macserial_location_name(info.legacyCountryIdx, info.modernCountryIdx).map { String(cString: $0) }
		let year = info.decodedYear != -1 ? String(info.decodedYear) : "???"
		let line = info.decodedCopy >= 0 ? "\(info.decodedLine) (copy \(info.decodedCopy + 1))" : "???"
		let model = info.appleModel.map { String(cString: $0) } ?? "???"
		let modelIdentifier = macserial_product_name(info.modelIndex).map { String(cString: $0) } ?? "???"

		return Decoded(country: country, year: year, week: weekRange(year: Int(info.decodedYear), week: Int(info.decodedWeek)),
		               line: line, model: model, modelIdentifier: modelIdentifier, isValid: info.valid)
	}

	/// Generates a random valid serial, board serial (MLB) and SmUUID for a model.
	static func generate(modelIdentifier: String) -> Generated? {
		guard let modelIndex = modelIdentifiers.firstIndex(of: modelIdentifier) else { return nil }
		var info = macserial_empty_info()
		info.modelIndex = Int32(modelIndex)
		guard get_serial(&info) else { return nil }

		var mlb = [CChar](repeating: 0, count: 32)
		get_mlb(&info, &mlb, mlb.count)

		let serial = [tupleString(info.country), tupleString(info.year), tupleString(info.week), tupleString(info.line), tupleString(info.model)].joined()
		return Generated(serialNumber: serial, boardSerialNumber: String(cString: mlb), smUUID: UUID().uuidString)
	}

	/// "MM.DD.YYYY-MM.DD.YYYY" for a week of a year, as macserial prints it.
	private static func weekRange(year: Int, week: Int) -> String? {
		guard year > 0, week > 0 else { return nil }
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC")!
		guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1 + 7 * (week - 1))) else { return nil }
		let formatter = DateFormatter()
		formatter.calendar = calendar
		formatter.timeZone = calendar.timeZone
		formatter.dateFormat = "MM.dd.yyyy"

		if week == 53 {
			// The last week runs to the end of the year.
			let lastDay = calendar.date(from: DateComponents(year: year, month: 12, day: 31))!
			return start == lastDay ? formatter.string(from: start) : formatter.string(from: start) + "-" + formatter.string(from: lastDay)
		}
		let end = calendar.date(byAdding: .day, value: 6, to: start)!
		return formatter.string(from: start) + "-" + formatter.string(from: end)
	}

	/// Reads a fixed-size C char array (imported as a tuple) as a string.
	private static func tupleString<T>(_ tuple: T) -> String {
		var copy = tuple
		return withUnsafeBytes(of: &copy) { buffer in
			String(cString: buffer.bindMemory(to: CChar.self).baseAddress!)
		}
	}
}
