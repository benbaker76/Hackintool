//
//  FramebufferModel.swift
//  Hackintool
//
//  State shared by the framebuffer pages: the chosen generation, table source and
//  platform ID, the loaded table, and the hardware the patches are generated for.
//

import Foundation

final class FramebufferModel {
	private(set) var generation: IntelGeneration
	private(set) var source: FramebufferTable.Source
	private(set) var table: FramebufferTable?
	private(set) var index = 0

	private(set) var pciDevices: [PCIDevice] = []
	private(set) var audioDevices: [AudioDevice] = []
	private(set) var displays: [Display] = []

	/// The device ID chosen for "Inject Device ID", as an index into deviceIDs.
	var injectedDeviceIndex = 0

	/// The selected record before auto patching (original plus any applied existing patches);
	/// switching a quick fix off restores its fields from here.
	private var baseline: Framebuffer?

	private var observers: [() -> Void] = []
	private static let sourceKey = "FramebufferSource"

	init() {
		generation = IntelGeneration(name: Settings.intelGeneration) ?? Machine.shared.intelGeneration ?? .coffeeLake
		source = FramebufferTable.Source(rawValue: UserDefaults.standard.integer(forKey: FramebufferModel.sourceKey)) ?? .installedKext
	}

	func observe(_ observer: @escaping () -> Void) {
		observers.append(observer)
	}

	func notify() {
		observers.forEach { $0() }
	}

	// MARK: Selection

	var platformID: UInt32? {
		guard let table = table, table.platformIDs.indices.contains(index) else { return nil }
		return table.platformIDs[index]
	}

	var original: Framebuffer? { return table.map { $0.original[index] } }
	var modified: Framebuffer? { return table.map { $0.modified[index] } }

	var deviceIDs: [UInt32] { return FramebufferTable.deviceIDs(for: generation) }

	var context: PatchContext? {
		guard let table = table else { return nil }
		let ids = deviceIDs
		return PatchContext(table: table, index: index, pciDevices: pciDevices, audioDevices: audioDevices, displays: displays,
		                    injectedDeviceID: ids.indices.contains(injectedDeviceIndex) ? ids[injectedDeviceIndex] : nil)
	}

	/// Loads the hardware lists and the table, selecting this Mac's platform ID the first time.
	func load() {
		pciDevices = PCIDevice.all()
		audioDevices = AudioDevice.all()
		displays = Display.all()
		if Settings.platformID.isEmpty, let current = Machine.shared.platformID {
			Settings.platformID = current.hex8
		}
		reloadTable()
	}

	func setGeneration(_ generation: IntelGeneration) {
		self.generation = generation
		Settings.intelGeneration = generation.name
		reloadTable()
	}

	func setSource(_ source: FramebufferTable.Source) {
		self.source = source
		UserDefaults.standard.set(source.rawValue, forKey: FramebufferModel.sourceKey)
		reloadTable()
	}

	func select(index: Int) {
		guard let table = table, table.platformIDs.indices.contains(index) else { return }
		self.index = index
		Settings.platformID = table.platformIDs[index].hex8
		prepareSelection()
		notify()
	}

	/// Switches generation if needed and selects a platform ID (e.g. from a config.plist).
	func select(platformID: UInt32) {
		if let generation = FramebufferTable.generation(of: platformID), generation != self.generation {
			self.generation = generation
			Settings.intelGeneration = generation.name
			Settings.platformID = platformID.hex8
			reloadTable()
			return
		}
		if let found = table?.index(of: platformID) {
			select(index: found)
		}
	}

	private func reloadTable() {
		table = FramebufferTable.load(generation, from: source)
		let saved = Settings.platformID.hexOrDecimalValue.map { UInt32(truncatingIfNeeded: $0) }
		index = saved.flatMap { table?.index(of: $0) } ?? 0
		let gpuID = Machine.shared.integratedGPU?.deviceID ?? 0
		injectedDeviceIndex = deviceIDs.firstIndex(of: gpuID) ?? 0
		prepareSelection()
		notify()
	}

	/// Applies the running Mac's existing patches (if wanted) and the auto patches.
	private func prepareSelection() {
		guard let table = table else { return }
		if Settings.applyCurrentPatches, let igpu = Machine.igpuEntry() {
			let properties = igpu.properties
			FramebufferPatcher.applyProperties(properties, to: table, at: index)
			selectInjectedDeviceID(from: properties)
		}
		baseline = table.modified[index]
		FramebufferPatcher.applyAutoPatches(to: table, at: index)
	}

	/// Selects the device ID a "device-id" property spoofs, if it's one this generation supports.
	private func selectInjectedDeviceID(from properties: [String: Any]) {
		guard let value = IOValue.uint32(properties["device-id"]),
		      let found = deviceIDs.firstIndex(of: value & 0xFFFF) else { return }
		injectedDeviceIndex = found
	}

	// MARK: Editing

	func modify(_ change: (inout Framebuffer) -> Void) {
		guard let table = table else { return }
		change(&table.modified[index])
		notify()
	}

	/// Undoes quick fixes that were switched off and applies the ones switched on.
	func settingsChanged() {
		guard let table = table else { return }
		if let baseline = baseline {
			FramebufferPatcher.resetAutoPatches(to: table, at: index, baseline: baseline)
		}
		FramebufferPatcher.applyAutoPatches(to: table, at: index)
		notify()
	}

	/// Discards edits, then re-applies existing patches and quick fixes.
	func resetChanges() {
		table?.reset(at: index)
		prepareSelection()
		notify()
	}

	/// Finds `find` in the original records and writes `replace` at the same place in the edited
	/// ones (so quick fixes already applied don't stop a stock-bytes patch from matching).
	/// Returns the number of replacements.
	@discardableResult
	func findAndReplace(_ find: Data, with replace: Data) -> Int {
		guard let table = table, !find.isEmpty, find.count == replace.count else { return 0 }
		let pattern = [UInt8](find)
		let replacement = [UInt8](replace)
		var count = 0
		for record in table.original.indices {
			let original = table.original[record].bytes
			var modified = table.modified[record]
			var offset = 0
			while offset + pattern.count <= original.count {
				if Array(original[offset..<offset + pattern.count]) == pattern {
					modified.bytes.replaceSubrange(offset..<offset + pattern.count, with: replacement)
					count += 1
					offset += pattern.count
				} else {
					offset += 1
				}
			}
			table.modified[record] = modified
		}
		notify()
		return count
	}

	/// Loads framebuffer properties (from a config.plist or System Configs preset) into the editor.
	func apply(properties: [String: Any]) {
		if let id = IOValue.uint32(properties["AAPL,snb-platform-id"] ?? properties["AAPL,ig-platform-id"]) {
			select(platformID: id)
		}
		guard let table = table else { return }
		FramebufferPatcher.applyProperties(properties, to: table, at: index)
		selectInjectedDeviceID(from: properties)
		baseline = table.modified[index]
		FramebufferPatcher.applyAutoPatches(to: table, at: index)
		notify()
	}

	/// True when every connector is a disabled dummy: a headless (compute-only) IGPU setup.
	var isHeadless: Bool {
		guard let framebuffer = original else { return false }
		return framebuffer.connectors.allSatisfy { connector in
			(connector.index == -1 || connector.index == 0) && connector.busID == 0 && connector.pipe == 0 &&
				connector.type == ConnectorType.dummy.rawValue && (connector.flags == 0x20 || connector.flags == 0x40)
		}
	}
}
