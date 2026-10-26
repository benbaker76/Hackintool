//
//  Machine.swift
//  Hackintool
//
//  Facts about this computer that several sections share: model, Intel graphics
//  generation, platform ID and the integrated GPU.
//

import Foundation

/// Intel graphics generations with a framebuffer Hackintool can patch.
enum IntelGeneration: Int, CaseIterable {
	case sandyBridge, ivyBridge, haswell, broadwell, skylake, kabyLake, coffeeLake, iceLakeLP

	var name: String {
		return ["Sandy Bridge", "Ivy Bridge", "Haswell", "Broadwell", "Skylake", "Kaby Lake", "Coffee Lake", "Ice Lake (LP)"][rawValue]
	}

	var shortName: String {
		return ["SNB", "IVB", "HSW", "BDW", "SKL", "KBL", "CFL", "ICLLP"][rawValue]
	}

	init?(name: String) {
		guard let generation = IntelGeneration.allCases.first(where: { $0.name == name }) else { return nil }
		self = generation
	}

	/// The framebuffer kext for this generation, e.g. "AppleIntelSKLGraphicsFramebuffer".
	var framebufferKext: String? {
		return BundledData.framebufferDrivers[name]
	}
}

struct IntegratedGPU {
	let model: String
	let deviceID: UInt32
	let vendorID: UInt32
	/// Total VRAM in MB.
	let vramSize: UInt64
	/// Free VRAM in bytes.
	let vramFree: UInt64
}

final class Machine {
	static let shared = Machine()

	private init() {}

	/// e.g. "iMac19,1".
	private(set) lazy var modelIdentifier: String? = {
		return IORegistryEntry.firstService(matching: "IOPlatformExpertDevice")?.string("model")
	}()

	private(set) lazy var serialNumber: String? = {
		return IORegistryEntry(path: "IODeviceTree:/")?.string("IOPlatformSerialNumber")
	}()

	/// The Intel graphics generation, from the framebuffer driver that's loaded.
	private(set) lazy var intelGeneration: IntelGeneration? = {
		let controllers = ["AppleIntelMEIDriver", "AppleIntelAzulController", "AppleIntelFBController", "AppleIntelFramebufferController"]
		guard let bundleID = controllers.lazy.compactMap({ IORegistryEntry.firstService(matching: $0)?.string("CFBundleIdentifier") }).first else { return nil }
		return IntelGeneration.allCases.first { generation in
			generation.framebufferKext.map { bundleID.contains($0) } ?? false
		} ?? .sandyBridge
	}()

	/// The IGPU's AAPL,ig-platform-id (or AAPL,snb-platform-id on Sandy Bridge).
	private(set) lazy var platformID: UInt32? = {
		guard let igpu = Machine.igpuEntry() else { return nil }
		return IOValue.uint32(igpu.searchProperty("AAPL,ig-platform-id", parents: false) ?? igpu.searchProperty("AAPL,snb-platform-id", parents: false))
	}()

	private(set) lazy var integratedGPU: IntegratedGPU? = {
		guard let igpu = Machine.igpuEntry() else { return nil }
		return IntegratedGPU(model: IOValue.string(igpu.property("model")) ?? "???",
		                     deviceID: igpu.uint32("device-id") ?? 0,
		                     vendorID: igpu.uint32("vendor-id") ?? 0,
		                     vramSize: Machine.vramSize(of: igpu),
		                     vramFree: Machine.vramFreeBytes())
	}()

	/// The EFI device path text of the boot device, from IODeviceTree:/chosen.
	private(set) lazy var bootDevicePath: String? = {
		guard let data = IORegistryEntry(path: "IODeviceTree:/chosen")?.data("boot-device-path") else { return nil }
		return EFIDevicePath.text(forHardDrivePath: data)
	}()

	// MARK: Helpers

	static func igpuEntry() -> IORegistryEntry? {
		return IORegistryEntry.services(matching: "IOPCIDevice").first { $0.name == "IGPU" }
	}

	/// VRAM in MB, from "VRAM,totalsize" (bytes) or "VRAM,totalMB".
	static func vramSize(of device: IORegistryEntry) -> UInt64 {
		if let bytes = IOValue.uint64(device.searchProperty("VRAM,totalsize", parents: false)) {
			return bytes >> 20
		}
		return IOValue.uint64(device.searchProperty("VRAM,totalMB", parents: false)) ?? 0
	}

	static func vramFreeBytes() -> UInt64 {
		for accelerator in IORegistryEntry.services(matching: "IOAccelerator") {
			if let statistics = accelerator.property("PerformanceStatistics") as? [String: Any],
			   let free = (statistics["vramFreeBytes"] as? NSNumber)?.uint64Value {
				return free
			}
		}
		return 0
	}
}

/// Data files bundled in Resources.
enum BundledData {
	static func plist(_ name: String, in directory: String) -> Any? {
		guard let url = Bundle.main.url(forResource: name, withExtension: "plist", subdirectory: directory),
		      let data = try? Data(contentsOf: url) else { return nil }
		return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
	}

	/// Mac models from EveryMac, each a dictionary with "Name", "Model ID" and specs.
	static let systems: [[String: Any]] = plist("Systems", in: "EveryMac") as? [[String: Any]] ?? []
	static let framebufferDrivers: [String: String] = plist("FBDrivers", in: "Intel") as? [String: String] ?? [:]
	static let intelDeviceIDs: [String: Any] = plist("DeviceIDs", in: "Intel") as? [String: Any] ?? [:]
	static let intelGPUs: [String: Any] = plist("GPUs", in: "Intel") as? [String: Any] ?? [:]
	static let intelModels: [String: Any] = plist("Models", in: "Intel") as? [String: Any] ?? [:]
	static let intelSpoofAudio: [String: Any] = plist("SpoofAudio", in: "Intel") as? [String: Any] ?? [:]
	static let audioCodecs: [[String: Any]] = plist("AudioCodecs", in: "Intel") as? [[String: Any]] ?? []
	static let audioVendors: [String: Any] = plist("Vendors", in: "Audio") as? [String: Any] ?? [:]
}
