//
//  Utilities.swift
//  Hackintool
//
//  System maintenance tasks: installing kexts, rebuilding the kext cache, dumping
//  ACPI tables, AppleIntelInfo, and Windows registry files for dual boot.
//

import Cocoa

/// Runs admin commands one after another, echoing each command and its output.
final class AdminCommandLog {
	typealias Output = (_ text: String, _ style: Style) -> Void

	enum Style {
		case command, output, error, heading
	}

	private let output: Output

	init(output: @escaping Output) {
		self.output = output
	}

	func heading(_ text: String) {
		emit(text + "\n", .heading)
	}

	/// Runs a tool as root; returns whether it exited successfully.
	@discardableResult
	func run(_ launchPath: String, _ arguments: [String]) -> Bool {
		emit("\(launchPath) \(arguments.joined(separator: " "))\n", .command)
		guard let result = Privileges.shared.run(launchPath, arguments) else {
			emit(L("Authorization failed") + "\n", .error)
			return false
		}
		if !result.output.isEmpty {
			emit(result.output, .output)
		}
		if !result.error.isEmpty {
			emit(result.error, .error)
		}
		return result.succeeded
	}

	private func emit(_ text: String, _ style: Style) {
		if Thread.isMainThread {
			output(text, style)
		} else {
			DispatchQueue.main.async { self.output(text, style) }
		}
	}
}

enum Utilities {
	static var isBigSurOrLater: Bool {
		return ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 11, minorVersion: 0, patchVersion: 0))
	}

	static var isCatalinaOrLater: Bool {
		return ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 10, minorVersion: 15, patchVersion: 0))
	}

	/// Where third-party kexts go: /Library/Extensions on 10.11+.
	static var extensionsPath: String {
		let elCapitan = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 10, minorVersion: 11, patchVersion: 0))
		return elCapitan ? "/Library/Extensions" : "/System/Library/Extensions"
	}

	static func bundledKext(_ name: String) -> URL? {
		return Bundle.main.url(forResource: name, withExtension: "kext", subdirectory: "Kexts")
	}

	// MARK: Kexts

	static func install(_ kexts: [URL], to destination: String, log: AdminCommandLog) {
		makeRootWritableIfNeeded(log: log)
		for kext in kexts {
			log.heading(L("Installing '%@'...", kext.lastPathComponent))
			log.run("/bin/rm", ["-Rf", (destination as NSString).appendingPathComponent(kext.lastPathComponent)])
			log.run("/bin/cp", ["-R", kext.path, destination])
		}
		rebuildKextCache(log: log)
	}

	/// Fixes kext ownership and permissions, then rebuilds the kext cache (kmutil on macOS 11+).
	static func rebuildKextCache(log: AdminCommandLog) {
		log.heading(L("Rebuilding KextCache and Repairing Permissions..."))
		if isBigSurOrLater {
			// /System is a sealed read-only volume; only /Library/Extensions can be fixed up.
			log.run("/usr/sbin/chown", ["-R", "root:wheel", "/Library/Extensions"])
			log.run("/bin/chmod", ["-R", "755", "/Library/Extensions"])
			log.run("/usr/bin/kmutil", ["install", "--update-all"])
		} else {
			makeRootWritableIfNeeded(log: log)
			log.run("/usr/sbin/chown", ["-v", "-R", "root:wheel", "/System/Library/Extensions"])
			log.run("/usr/bin/touch", ["/System/Library/Extensions"])
			log.run("/bin/chmod", ["-v", "-R", "755", "/Library/Extensions"])
			log.run("/usr/sbin/chown", ["-v", "-R", "root:wheel", "/Library/Extensions"])
			log.run("/usr/bin/touch", ["/Library/Extensions"])
			log.run("/usr/sbin/kextcache", ["-i", "/"])
		}
	}

	/// macOS 10.15 mounts the system volume read-only; remount it writable for /S/L/E changes.
	static func makeRootWritableIfNeeded(log: AdminCommandLog) {
		guard isCatalinaOrLater, !isBigSurOrLater, !isRootWritable else { return }
		disableGatekeeperAndMountRootWritable(log: log)
	}

	static func disableGatekeeperAndMountRootWritable(log: AdminCommandLog) {
		log.run("/usr/sbin/spctl", ["--master-disable"])
		if !isBigSurOrLater {
			log.run("/sbin/mount", ["-uw", "/"])
			log.run("/usr/bin/killall", ["Finder"])
		}
	}

	static var isRootWritable: Bool {
		var info = statfs()
		return statfs("/", &info) == 0 && (info.f_flags & UInt32(MNT_RDONLY)) == 0
	}

	/// Atheros AR9xxx support: IO80211Family (10.15) or AirPortAtheros40 (earlier).
	static func installAtherosKext(log: AdminCommandLog) {
		if isCatalinaOrLater {
			guard let kext = bundledKext("IO80211Family") else { return }
			// Keep a copy of the original on the Desktop.
			log.run("/bin/cp", ["-r", "/System/Library/Extensions/IO80211Family.kext", KextJobs.desktop.appendingPathComponent("IO80211Family.kext").path])
			install([kext], to: "/System/Library/Extensions", log: log)
		} else if let kext = bundledKext("AirPortAtheros40") {
			install([kext], to: extensionsPath, log: log)
		}
	}

	// MARK: ACPI

	/// Saves the DSDT and SSDTs to `folder` and disassembles them with the bundled iasl.
	static func dumpACPITables(to folder: URL, output: @escaping (String, Bool) -> Void) {
		guard let expert = IORegistryEntry.firstService(matching: "AppleACPIPlatformExpert"),
		      let tables = expert.property("ACPI Tables") as? [String: Data] else {
			output(L("No ACPI tables found.") + "\n", true)
			return
		}
		let names = tables.keys.filter { $0.hasPrefix("DSDT") || $0.hasPrefix("SSDT") }.sorted()
		for name in names {
			try? tables[name]?.write(to: folder.appendingPathComponent(name + ".aml"))
		}
		guard let iasl = Bundle.main.url(forResource: "iasl", withExtension: nil, subdirectory: "Utilities") else { return }
		Shell.runStreaming(iasl.path, ["-dl", "-f", "DSDT.aml"], currentDirectory: folder.path, output: output)
		for name in names where name.hasPrefix("SSDT") {
			Shell.runStreaming(iasl.path, ["-dl", "-fe", "DSDT.aml", name + ".aml"], currentDirectory: folder.path, output: output)
		}
	}

	// MARK: AppleIntelInfo

	struct AppleIntelInfoOptions {
		var enableHWP = Settings.aiiEnableHWP
		var logCStates = Settings.aiiLogCStates
		var logIGPU = Settings.aiiLogIGPU
		var logIPGStyle = Settings.aiiLogIPGStyle
		var logIntelRegs = Settings.aiiLogIntelRegs
		var logMSRs = Settings.aiiLogMSRs
	}

	/// Loads AppleIntelInfo with the chosen options, waits while it samples, and returns its report.
	static func runAppleIntelInfo(_ options: AppleIntelInfoOptions, log: AdminCommandLog, waitWhileLogging: (TimeInterval) -> Void) -> String? {
		guard let source = bundledKext("AppleIntelInfo") else { return nil }
		let temp = FileManager.default.temporaryDirectory.appendingPathComponent("AppleIntelInfo-\(UUID().uuidString)")
		let kext = temp.appendingPathComponent("AppleIntelInfo.kext")
		let report = temp.appendingPathComponent("AppleIntelInfo.dat")
		try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
		defer { log.run("/bin/rm", ["-rf", temp.path]) }

		do {
			try FileManager.default.copyItem(at: source, to: kext)
		} catch {
			return nil
		}
		let infoURL = kext.appendingPathComponent("Contents/Info.plist")
		if let info = NSMutableDictionary(contentsOf: infoURL),
		   let personalities = (info["IOKitPersonalities"] as? NSDictionary)?.mutableCopy() as? NSMutableDictionary,
		   let personality = (personalities["AppleIntelInfo"] as? NSDictionary)?.mutableCopy() as? NSMutableDictionary {
			personality["enableHWP"] = options.enableHWP
			personality["logCStates"] = options.logCStates
			personality["logIGPU"] = options.logIGPU
			personality["logIPGStyle"] = options.logIPGStyle
			personality["logIntelRegs"] = options.logIntelRegs
			personality["logMSRs"] = options.logMSRs
			personalities["AppleIntelInfo"] = personality
			info["IOKitPersonalities"] = personalities
			info.write(to: infoURL, atomically: true)
		}

		log.run("/usr/sbin/chown", ["-R", "root:wheel", kext.path])
		log.run("/bin/chmod", ["-R", "755", kext.path])
		log.run("/sbin/kextload", [kext.path])
		if options.logCStates {
			waitWhileLogging(30)
		}
		log.run("/sbin/kextunload", [kext.path])
		log.run("/bin/cp", ["/tmp/AppleIntelInfo.dat", report.path])
		log.run("/usr/sbin/chown", [NSUserName(), report.path])
		return try? String(contentsOf: report, encoding: .utf8)
	}

	// MARK: Windows

	/// Copies the registry files that make Windows keep the hardware clock in UTC.
	static func createWindowsUTCRegistryFiles(in folder: URL) -> [URL] {
		return ["WinUTCOn", "WinUTCOff"].compactMap { name in
			guard let source = Bundle.main.url(forResource: name, withExtension: "reg", subdirectory: "Windows") else { return nil }
			let destination = folder.appendingPathComponent(name + ".reg")
			try? FileManager.default.removeItem(at: destination)
			return (try? FileManager.default.copyItem(at: source, to: destination)) != nil ? destination : nil
		}
	}
}
