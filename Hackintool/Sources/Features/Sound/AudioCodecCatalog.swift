//
//  AudioCodecCatalog.swift
//  Hackintool
//
//  Builds the bundled Audio/Codecs.plist (codec names, layout IDs, revisions and
//  supported kernels) from a checkout of AppleALC's Resources folder.
//

import Foundation

enum AudioCodecCatalog {
	static func generate(fromAppleALCResources folder: URL) -> [[String: Any]] {
		let fileManager = FileManager.default
		let entries = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
		var codecs: [[String: Any]] = []
		for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
			guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
			      let info = NSDictionary(contentsOf: entry.appendingPathComponent("Info.plist")) as? [String: Any],
			      let name = info["CodecName"] as? String else { continue }
			let vendorID = (info["Vendor"] as? String).flatMap { BundledData.audioVendors[$0] as? NSNumber }?.uint32Value ?? 0
			let codecID = (info["CodecID"] as? NSNumber)?.uint32Value ?? 0
			let layouts = (info["Files"] as? [String: Any])?["Layouts"] as? [[String: Any]] ?? []
			let revisions = info["Revisions"] as? [NSNumber] ?? []
			let patches = info["Patches"] as? [[String: Any]] ?? []
			let minKernel = patches.compactMap { ($0["MinKernel"] as? NSNumber)?.intValue }.min() ?? 255
			let maxKernel = patches.compactMap { ($0["MaxKernel"] as? NSNumber)?.intValue }.max() ?? 0
			codecs.append([
				"CodecName": name,
				"CodecID": NSNumber(value: vendorID << 16 | (codecID & 0xFFFF)),
				"LayoutIDs": layouts.compactMap { $0["Id"] },
				"Revisions": revisions.map { String(format: "0x%06X", $0.uint32Value) },
				"MinKernel": minKernel,
				"MaxKernel": maxKernel,
			])
		}
		return codecs
	}
}
