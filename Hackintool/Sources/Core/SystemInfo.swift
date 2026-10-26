//
//  SystemInfo.swift
//  Hackintool
//
//  Host, OS, kernel, memory and CPU details from sysctl.
//

import Foundation

enum SystemInfo {
	static func sysctlString(_ name: String) -> String? {
		var length = 0
		guard sysctlbyname(name, nil, &length, nil, 0) == 0, length > 0 else { return nil }
		var buffer = [CChar](repeating: 0, count: length)
		guard sysctlbyname(name, &buffer, &length, nil, 0) == 0 else { return nil }
		return String(cString: buffer)
	}

	static func sysctlInt64(_ name: String) -> Int64? {
		var value: Int64 = 0
		var length = MemoryLayout<Int64>.size
		guard sysctlbyname(name, &value, &length, nil, 0) == 0 else { return nil }
		return value
	}

	static var hostName: String {
		return sysctlString("kern.hostname") ?? "???"
	}

	/// e.g. "Darwin 23.4.0 x86_64".
	static var kernel: String {
		return [sysctlString("kern.ostype"), sysctlString("kern.osrelease"), sysctlString("hw.machine")]
			.compactMap { $0 }
			.joined(separator: " ")
	}

	static var cpu: String {
		return sysctlString("machdep.cpu.brand_string") ?? "???"
	}

	static var memorySize: String {
		return sysctlInt64("hw.memsize").map { ByteCount.string(for: Double($0)) } ?? "???"
	}

	static var isAppleSilicon: Bool {
		return sysctlInt64("hw.optional.arm64") == 1
	}

	/// e.g. "macOS Sonoma Version 14.4 (Build 23E214)".
	static var osName: String {
		let processInfo = ProcessInfo.processInfo
		return codeName(for: processInfo.operatingSystemVersion) + " " + processInfo.operatingSystemVersionString
	}

	static func codeName(for version: OperatingSystemVersion) -> String {
		switch (version.majorVersion, version.minorVersion) {
		case (10, 4): return "Mac OS X Tiger"
		case (10, 5): return "Mac OS X Leopard"
		case (10, 6): return "Mac OS X Snow Leopard"
		case (10, 7): return "Mac OS X Lion"
		case (10, 8): return "OS X Mountain Lion"
		case (10, 9): return "OS X Mavericks"
		case (10, 10): return "OS X Yosemite"
		case (10, 11): return "OS X El Capitan"
		case (10, 12): return "macOS Sierra"
		case (10, 13): return "macOS High Sierra"
		case (10, 14): return "macOS Mojave"
		case (10, 15): return "macOS Catalina"
		case (11, _): return "macOS Big Sur"
		case (12, _): return "macOS Monterey"
		case (13, _): return "macOS Ventura"
		case (14, _): return "macOS Sonoma"
		case (15, _): return "macOS Sequoia"
		case (26, _): return "macOS Tahoe"
		case (let major, _) where major > 26: return "macOS (Future \(major))"
		default: return "macOS (Unknown)"
		}
	}
}

enum ByteCount {
	/// "16.00 GB" style, using 1024 multiples like the original app.
	static func string(for bytes: Double) -> String {
		let units = ["bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"]
		var value = bytes
		var unit = 0
		while value > 1024 && unit < units.count - 1 {
			value /= 1024
			unit += 1
		}
		return String(format: "%4.2f %@", value, units[unit])
	}
}
