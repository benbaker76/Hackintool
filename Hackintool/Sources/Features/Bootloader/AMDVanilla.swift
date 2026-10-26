//
//  AMDVanilla.swift
//  Hackintool
//
//  The AMD Vanilla OpenCore kernel patches (github.com/AMD-OSX/AMD_Vanilla) that let
//  macOS boot on AMD CPUs: downloading them, setting the core count, checking a
//  config.plist against them, and merging them in.
//

import Foundation

struct AMDVanillaPatch {
	enum Kind {
		/// "Force cpuid_cores_per_package": the physical core count goes in the second Replace byte.
		case coreCount
		/// One of the _mtrr_update_action PAT fixes; only one per macOS range may be enabled.
		case pat
		case standard
	}

	/// Position in patches.plist.
	let index: Int
	/// The patch exactly as AMD_Vanilla ships it (OpenCore Kernel ▸ Patch format).
	let entry: [String: Any]

	var comment: String { return entry["Comment"] as? String ?? "" }
	var identifier: String { return entry["Identifier"] as? String ?? "" }
	var minKernel: String { return entry["MinKernel"] as? String ?? "" }
	var maxKernel: String { return entry["MaxKernel"] as? String ?? "" }
	var isEnabledByDefault: Bool { return entry["Enabled"] as? Bool ?? false }

	var kind: Kind {
		if comment.contains("cpuid_cores_per_package") {
			return .coreCount
		}
		if comment.contains("_mtrr_update_action") {
			return .pat
		}
		return .standard
	}

	/// The core count patches share a comment, so the kernel range tells them apart.
	func matches(_ existing: NSDictionary) -> Bool {
		return existing["Identifier"] as? String == identifier
			&& existing["Comment"] as? String == comment
			&& existing["MinKernel"] as? String ?? "" == minKernel
	}

	/// "10.13 – 10.14", "13.3+" and so on.
	var macOSRange: String {
		let low = AMDVanilla.macOSVersion(forKernel: minKernel)
		let high = AMDVanilla.macOSVersion(forKernel: maxKernel)
		switch (low, high) {
		case (let low?, let high?): return low == high ? low : "\(low) – \(high)"
		case (let low?, nil): return "\(low)+"
		case (nil, let high?): return "≤ \(high)"
		default: return L("All")
		}
	}

	/// The patch to write, with the user's choices filled in.
	func configEntry(enabled: Bool, coreCount: Int) -> NSMutableDictionary {
		let dictionary = NSMutableDictionary(dictionary: entry)
		dictionary["Enabled"] = enabled
		if kind == .coreCount, var replace = entry["Replace"] as? Data, replace.count > 1 {
			replace[replace.startIndex + 1] = UInt8(clamping: coreCount)
			dictionary["Replace"] = replace
		}
		return dictionary
	}
}

/// How a patch compares with the copy in a config.plist.
enum AMDVanillaPatchState {
	case missing
	/// Same as AMD_Vanilla's (apart from the core count).
	case current(enabled: Bool)
	/// An older or edited version.
	case outdated(enabled: Bool)

	var isEnabled: Bool {
		switch self {
		case .missing: return false
		case .current(let enabled), .outdated(let enabled): return enabled
		}
	}

	var title: String {
		switch self {
		case .missing: return L("Not in config")
		case .current(let enabled): return enabled ? L("Enabled") : L("Disabled")
		case .outdated(let enabled): return enabled ? L("Enabled (outdated)") : L("Disabled (outdated)")
		}
	}
}

/// What a config.plist has of the AMD Vanilla patches.
struct AMDVanillaReport {
	var states: [Int: AMDVanillaPatchState] = [:]
	/// Kernel ▸ Quirks ▸ ProvideCurrentCpuInfo; nil if it isn't set at all.
	var provideCurrentCpuInfo: Bool?
	/// The core counts written in the config's core count patches.
	var coreCounts: Set<Int> = []
	/// Problems worth pointing out.
	var warnings: [String] = []

	init(config: NSDictionary, patches: [AMDVanillaPatch]) {
		let kernel = config["Kernel"] as? NSDictionary
		provideCurrentCpuInfo = (kernel?["Quirks"] as? NSDictionary)?["ProvideCurrentCpuInfo"] as? Bool
		let existing = (kernel?["Patch"] as? NSArray)?.compactMap { $0 as? NSDictionary } ?? []

		for patch in patches {
			guard let entry = existing.first(where: patch.matches) else {
				states[patch.index] = .missing
				continue
			}
			let enabled = entry["Enabled"] as? Bool ?? false
			states[patch.index] = AMDVanillaReport.isSame(entry, as: patch) ? .current(enabled: enabled) : .outdated(enabled: enabled)
			if patch.kind == .coreCount, let replace = entry["Replace"] as? Data, replace.count > 1 {
				coreCounts.insert(Int(replace[replace.startIndex + 1]))
			}
		}

		let found = patches.filter { if case .missing = states[$0.index]! { return false } else { return true } }
		guard !found.isEmpty else { return }
		if provideCurrentCpuInfo != true {
			warnings.append(L("ProvideCurrentCpuInfo is off. AMD Vanilla needs it or macOS won't boot."))
		}
		if coreCounts.contains(0) {
			warnings.append(L("The core count patches still have a core count of 0."))
		} else if coreCounts.count > 1 {
			warnings.append(L("The core count patches don't all have the same core count."))
		}
		for pair in AMDVanilla.exclusiveGroups(patches) where pair.filter({ states[$0.index]?.isEnabled == true }).count > 1 {
			warnings.append(L("More than one PAT patch is enabled for macOS %@. Only use one.", pair[0].macOSRange))
		}
		if patches.contains(where: { if case .outdated = states[$0.index]! { return true } else { return false } }) {
			warnings.append(L("Some patches are out of date. Apply to update them."))
		}
	}

	/// Compares everything except Enabled and the core count byte.
	private static func isSame(_ entry: NSDictionary, as patch: AMDVanillaPatch) -> Bool {
		for (key, value) in patch.entry where key != "Enabled" {
			let ours = entry[key] as? NSObject
			if key == "Replace", patch.kind == .coreCount, var theirs = value as? Data, var mine = ours as? Data,
			   theirs.count == mine.count, theirs.count > 1 {
				theirs[theirs.startIndex + 1] = 0
				mine[mine.startIndex + 1] = 0
				if theirs != mine { return false }
				continue
			}
			if ours != value as? NSObject { return false }
		}
		return true
	}
}

enum AMDVanilla {
	static let sourceURL = URL(string: "https://raw.githubusercontent.com/AMD-OSX/AMD_Vanilla/master/patches.plist")!
	static let projectURL = URL(string: "https://github.com/AMD-OSX/AMD_Vanilla")!

	/// The last downloaded patches.plist.
	static var cacheURL: URL? {
		return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("AMD_Vanilla-patches.plist")
	}

	static func parse(_ data: Data) -> [AMDVanillaPatch]? {
		guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
		      let patches = (plist["Kernel"] as? [String: Any])?["Patch"] as? [[String: Any]], !patches.isEmpty else { return nil }
		return patches.enumerated().map { AMDVanillaPatch(index: $0.offset, entry: $0.element) }
	}

	/// The cached copy and when it was downloaded.
	static func cached() -> (patches: [AMDVanillaPatch], date: Date?)? {
		guard let url = cacheURL, let data = try? Data(contentsOf: url), let patches = parse(data) else { return nil }
		let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
		return (patches, date)
	}

	/// Downloads patches.plist, caching it; calls back on the main queue.
	static func download(completion: @escaping ([AMDVanillaPatch]?) -> Void) {
		var request = URLRequest(url: sourceURL)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		URLSession.shared.dataTask(with: request) { data, _, _ in
			let patches = data.flatMap(parse)
			if patches != nil, let data = data, let url = cacheURL {
				try? data.write(to: url, options: .atomic)
			}
			DispatchQueue.main.async { completion(patches) }
		}.resume()
	}

	// MARK: The CPU

	static var isAMDCPU: Bool {
		return SystemInfo.sysctlString("machdep.cpu.vendor") == "AuthenticAMD"
	}

	/// The physical core count, if this is an AMD machine. The brand string ("AMD Ryzen 7 5800X
	/// 8-Core Processor") is preferred because the kernel's own count comes from the patched CPUID.
	static var detectedCoreCount: Int? {
		guard isAMDCPU else { return nil }
		let brand = SystemInfo.cpu
		if let range = brand.range(of: #"(\d+)-Core"#, options: .regularExpression),
		   let count = Int(brand[range].dropLast(5)), count > 0 {
			return count
		}
		return SystemInfo.sysctlInt64("hw.physicalcpu").map(Int.init)
	}

	// MARK: Patch groups

	/// PAT patches for the same macOS range: Algrey's and Shaneee's, which mustn't both be enabled.
	static func exclusiveGroups(_ patches: [AMDVanillaPatch]) -> [[AMDVanillaPatch]] {
		let pats = patches.filter { $0.kind == .pat }
		var groups: [String: [AMDVanillaPatch]] = [:]
		for patch in pats {
			groups[patch.minKernel + "-" + patch.maxKernel, default: []].append(patch)
		}
		return groups.values.filter { $0.count > 1 }.sorted { $0[0].index < $1[0].index }
	}

	/// The newest macOS the patches cover, e.g. "26".
	static func newestMacOS(_ patches: [AMDVanillaPatch]) -> String? {
		let newest = patches.compactMap { Int($0.maxKernel.split(separator: ".").first ?? "") }.max()
		return newest.flatMap { macOSVersion(forKernel: "\($0).99.99") }
	}

	/// Whether the running kernel is newer than every patch's MaxKernel.
	static func isRunningKernelCovered(_ patches: [AMDVanillaPatch]) -> Bool {
		guard let running = SystemInfo.sysctlString("kern.osrelease"),
		      let major = Int(running.split(separator: ".").first ?? "") else { return true }
		let newest = patches.compactMap { Int($0.maxKernel.split(separator: ".").first ?? "") }.max() ?? 0
		return major <= newest
	}

	// MARK: Merging

	/// Replaces the AMD Vanilla patches in `config` with `patches`, enabling those in `enabled`.
	/// Other patches are left alone; the new set goes where the old one was, or at the end.
	static func apply(_ patches: [AMDVanillaPatch], enabled: Set<Int>, coreCount: Int, provideCurrentCpuInfo: Bool, to config: ConfigPlist) {
		let array = config.kernelPatches()
		var insertAt: Int?
		for index in stride(from: array.count - 1, through: 0, by: -1) {
			guard let existing = array[index] as? NSDictionary, patches.contains(where: { $0.matches(existing) }) else { continue }
			array.removeObject(at: index)
			insertAt = index
		}
		let entries = patches.map { $0.configEntry(enabled: enabled.contains($0.index), coreCount: coreCount) }
		array.insert(entries, at: IndexSet(integersIn: (insertAt ?? array.count)..<((insertAt ?? array.count) + entries.count)))
		if provideCurrentCpuInfo {
			config.kernelQuirks["ProvideCurrentCpuInfo"] = true
		}
	}

	// MARK: Kernel versions

	/// macOS version for a Darwin version: "17.0.0" → "10.13", "22.4.0" → "13.3", "25.99.99" → "26".
	static func macOSVersion(forKernel kernel: String) -> String? {
		let parts = kernel.split(separator: ".").compactMap { Int($0) }
		guard let major = parts.first else { return nil }
		let minor = parts.count > 1 ? parts[1] : 0
		let name: String
		switch major {
		case 0..<20: name = "10.\(major - 4)"
		case 20..<25: name = "\(major - 9)"
		case 25: name = "26"
		default: name = "\(major)"
		}
		// On macOS 11 and later, Darwin minor x is roughly macOS minor x-1 (22.4 → 13.3);
		// .99 means "any". 10.x minors don't line up, so those show the major release only.
		if minor == 0 || minor == 99 || major < 20 {
			return name
		}
		return "\(name).\(minor - 1)"
	}
}
