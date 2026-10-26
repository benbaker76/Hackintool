//
//  AMDVanillaViewController.swift
//  Hackintool
//
//  Bootloader ▸ AMD Vanilla: the OpenCore kernel patches for AMD CPUs, with the core count
//  filled in, checked against a config.plist and merged into it.
//

import Cocoa

final class AMDVanillaViewController: NSViewController, SectionContent {
	private struct Row {
		let patch: AMDVanillaPatch
		let state: AMDVanillaPatchState?
	}

	private let info = PropertyListViewController(showsGroupHeaders: false)
	private var patches: [AMDVanillaPatch] = []
	private var downloadedDate: Date?
	private var selected = Set<Int>()
	/// The config.plist opened for checking; Apply writes back to it.
	private var configURL: URL?
	private var report: AMDVanillaReport?

	private static let coreCounts = [2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 32, 48, 64, 96, 128]

	private lazy var table = DataTableViewController<Row>(columns: [
		DataColumn("Select", "", width: 24) { [unowned self] in self.selected.contains($0.patch.index) ? "1" : "0" }
			.with(customView: { [unowned self] row in self.checkbox(for: row) }),
		DataColumn("macOS", "macOS", width: 110, sortKey: { .number(Double($0.patch.index)) }) { $0.patch.macOSRange },
		DataColumn("Comment", "Comment", width: 420) { $0.patch.comment },
		DataColumn("Identifier", "Identifier", width: 190) { $0.patch.identifier },
		DataColumn("Status", "Status", width: 150) { $0.state?.title ?? "" },
	])
	private lazy var coreCountPopUp = ControlBar.popUp([], target: self, action: #selector(coreCountChanged(_:)))
	private lazy var quirkCheckbox = Form.checkbox("Enable ProvideCurrentCpuInfo", target: self, action: #selector(ignore(_:)))
	private lazy var applyButton = ControlBar.button("Apply to config.plist", symbol: .wand, target: self, action: #selector(apply(_:)))

	override func loadView() {
		addChild(info)
		addChild(table)
		quirkCheckbox.state = .on
		quirkCheckbox.toolTip = L("AMD Vanilla needs the ProvideCurrentCpuInfo kernel quirk; without it macOS won't boot.")
		table.rowColor = { row in
			switch row.state {
			case .outdated?: return NSColor.systemOrange.withAlphaComponent(0.15)
			default: return nil
			}
		}

		let header = ControlBar.make([ControlBar.label("Physical Cores"), coreCountPopUp], trailing: [
			ControlBar.button("Open config.plist…", symbol: .folder, target: self, action: #selector(openConfig(_:))),
			ControlBar.button("Download Latest", symbol: .refresh, target: self, action: #selector(downloadLatest(_:))),
			ControlBar.iconButton(.gitHub, toolTip: "AMD_Vanilla on GitHub", target: self, action: #selector(openProject(_:))),
		])
		let footer = ControlBar.make([
			ControlBar.label("Replaces the AMD Vanilla patches in config.plist with the ticked ones; a backup is made first."),
		], trailing: [quirkCheckbox, applyButton])

		let split = NSSplitView()
		split.isVertical = false
		split.dividerStyle = .thin
		split.addArrangedSubview(ControlBar.stack(header: header, content: info.view))
		split.addArrangedSubview(ControlBar.stack(header: ControlBar.make([ControlBar.heading("Patches")]), content: table.view, footer: footer))
		let infoHeight = split.arrangedSubviews[0].heightAnchor.constraint(equalToConstant: 200)
		infoHeight.priority = .defaultLow
		infoHeight.isActive = true
		view = split
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		fillCoreCounts(selecting: AMDVanilla.detectedCoreCount)
		if let cached = AMDVanilla.cached() {
			setPatches(cached.patches, date: cached.date)
		}
		update()
		downloadLatest(nil)
	}

	// MARK: State

	private var coreCount: Int? {
		return coreCountPopUp.selectedItem?.representedObject as? Int
	}

	private func fillCoreCounts(selecting count: Int?) {
		coreCountPopUp.removeAllItems()
		coreCountPopUp.addItem(withTitle: L("Choose…"))
		let detected = AMDVanilla.detectedCoreCount
		for value in Set(AMDVanilla.coreCountChoices(Self.coreCounts, plus: [detected, count])).sorted() {
			let title = value == detected ? L("%d (this CPU)", value) : String(value)
			coreCountPopUp.addItem(withTitle: title)
			coreCountPopUp.lastItem?.representedObject = value
		}
		if let count = count, let item = coreCountPopUp.itemArray.first(where: { $0.representedObject as? Int == count }) {
			coreCountPopUp.select(item)
		} else {
			coreCountPopUp.selectItem(at: 0)
		}
	}

	private func setPatches(_ patches: [AMDVanillaPatch], date: Date?) {
		self.patches = patches
		downloadedDate = date
		resetSelection()
	}

	/// Ticks what the opened config has enabled, or AMD_Vanilla's defaults.
	private func resetSelection() {
		selected = Set(patches.filter { patch in
			if let state = report?.states[patch.index], case .missing = state {
				return patch.isEnabledByDefault
			}
			return report?.states[patch.index]?.isEnabled ?? patch.isEnabledByDefault
		}.map { $0.index })
	}

	private func update() {
		table.setRows(patches.map { Row(patch: $0, state: report?.states[$0.index]) })

		var items: [PropertyItem] = []
		items.append(PropertyItem("CPU", SystemInfo.cpu + (AMDVanilla.isAMDCPU ? "" : " — " + L("not an AMD CPU; set the core count for the target machine"))))
		if patches.isEmpty {
			items.append(PropertyItem("Patches", L("Not downloaded yet")))
		} else {
			let date = downloadedDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? "?"
			items.append(PropertyItem("Patches", L("%d from AMD_Vanilla (downloaded %@)", patches.count, date)))
			if let newest = AMDVanilla.newestMacOS(patches) {
				let covered = AMDVanilla.isRunningKernelCovered(patches)
				items.append(PropertyItem("Supports", L("Up to macOS %@", newest) + (covered ? "" : " — " + L("not the running macOS yet"))))
			}
		}
		if BootloaderConfigFormat.current == .clover {
			items.append(PropertyItem("Bootloader", L("AMD Vanilla patches are for OpenCore only.")))
		}
		if let url = configURL, let report = report {
			items.append(PropertyItem("config.plist", url.path))
			let quirk: String
			switch report.provideCurrentCpuInfo {
			case true?: quirk = L("Enabled")
			case false?: quirk = L("Disabled")
			case nil: quirk = L("Not set")
			}
			items.append(PropertyItem("ProvideCurrentCpuInfo", quirk))
			if !report.coreCounts.isEmpty {
				items.append(PropertyItem("Core Count in config", report.coreCounts.sorted().map(String.init).joined(separator: ", ")))
			}
			for warning in report.warnings {
				items.append(PropertyItem("Warning", warning))
			}
			if report.warnings.isEmpty, report.states.values.contains(where: { $0.isEnabled }) {
				items.append(PropertyItem("Status", L("Up to date")))
			}
		} else {
			items.append(PropertyItem("config.plist", L("Open one to check it against AMD_Vanilla")))
		}
		info.setItems(items)
		applyButton.isEnabled = !patches.isEmpty && BootloaderConfigFormat.current == .openCore
	}

	// MARK: SectionContent

	var canRefresh: Bool { return true }
	func refresh() {
		reloadConfig()
		update()
	}
	var searchPlaceholder: String? { return table.searchPlaceholder }
	func search(_ text: String) { table.search(text) }

	// MARK: Actions

	@objc private func ignore(_ sender: Any?) {}

	@objc private func coreCountChanged(_ sender: NSPopUpButton) {}

	@objc private func openProject(_ sender: Any?) {
		NSWorkspace.shared.open(AMDVanilla.projectURL)
	}

	@objc private func downloadLatest(_ sender: Any?) {
		AMDVanilla.download { [weak self] patches in
			guard let self = self else { return }
			guard let patches = patches else {
				if sender != nil {
					Alerts.error("Couldn't download the AMD Vanilla patches.", AMDVanilla.sourceURL.absoluteString)
				}
				return
			}
			self.setPatches(patches, date: Date())
			self.reloadConfig()
			self.update()
		}
	}

	@objc private func openConfig(_ sender: Any?) {
		ConfigPlistPicker.mountBootEFI { efiURL in
			FilePanels.open(allowedExtensions: ["plist"], directory: efiURL?.appendingPathComponent(BootloaderConfigFormat.openCore.efiDirectory)) { [weak self] url in
				guard let self = self else { return }
				guard NSDictionary(contentsOf: url) != nil else {
					Alerts.error("Couldn't read the config.plist.", url.path)
					return
				}
				self.configURL = url
				self.reloadConfig()
				if let count = self.report?.coreCounts.first(where: { $0 > 0 }), self.report?.coreCounts.count == 1 {
					self.fillCoreCounts(selecting: count)
				}
				self.update()
			}
		}
	}

	/// Re-reads the opened config.plist and re-ticks the patches to match it.
	private func reloadConfig() {
		guard let url = configURL, let dictionary = NSDictionary(contentsOf: url) else {
			report = nil
			return
		}
		report = AMDVanillaReport(config: dictionary, patches: patches)
		resetSelection()
	}

	private func checkbox(for row: Row) -> NSView {
		let checkbox = AMDVanillaCheckbox(index: row.patch.index, target: self, action: #selector(toggle(_:)))
		checkbox.state = selected.contains(row.patch.index) ? .on : .off
		return checkbox
	}

	@objc private func toggle(_ sender: AMDVanillaCheckbox) {
		guard sender.state == .on else {
			selected.remove(sender.index)
			return
		}
		selected.insert(sender.index)
		// Algrey's and Shaneee's PAT fixes are alternatives: ticking one unticks the other.
		if let group = AMDVanilla.exclusiveGroups(patches).first(where: { $0.contains { $0.index == sender.index } }) {
			let others = group.map { $0.index }.filter { $0 != sender.index && selected.contains($0) }
			if !others.isEmpty {
				others.forEach { selected.remove($0) }
				table.reload()
			}
		}
	}

	@objc private func apply(_ sender: Any?) {
		guard let coreCount = coreCount else {
			Alerts.show("Choose the core count first.", "Use the number of physical cores, not threads.")
			return
		}
		guard !selected.isEmpty else {
			Alerts.show("No patches selected.", "Tick the patches you want to add first.")
			return
		}
		let patches = self.patches
		let enabled = selected
		let quirk = quirkCheckbox.state == .on
		let message = L("Write %d AMD Vanilla patches (%d enabled) for %d cores?", patches.count, enabled.count, coreCount)
		Alerts.confirm("AMD Vanilla", message, confirmTitle: "Apply") { [weak self] confirmed in
			guard confirmed, let self = self else { return }
			let write = { (config: ConfigPlist, url: URL) in
				AMDVanilla.apply(patches, enabled: enabled, coreCount: coreCount, provideCurrentCpuInfo: quirk, to: config)
				do {
					try config.write(to: url)
				} catch {
					Alerts.error("Couldn't write the config.plist.", error.localizedDescription)
					return
				}
				self.configURL = url
				self.reloadConfig()
				self.update()
			}
			// Re-read the opened file so changes made elsewhere since aren't lost.
			if let url = self.configURL, let config = ConfigPlist(contentsOf: url, format: .openCore) {
				write(config, url)
			} else {
				ConfigPlistPicker.choose(completion: write)
			}
		}
	}
}

extension AMDVanilla {
	/// The usual core counts plus any detected or configured ones that aren't among them.
	static func coreCountChoices(_ common: [Int], plus extra: [Int?]) -> [Int] {
		return common + extra.compactMap { $0 }.filter { $0 > 0 && $0 <= 255 }
	}
}

/// A checkbox that remembers which patch it toggles.
final class AMDVanillaCheckbox: NSButton {
	let index: Int

	init(index: Int, target: AnyObject, action: Selector) {
		self.index = index
		super.init(frame: .zero)
		setButtonType(.switch)
		title = ""
		self.target = target
		self.action = action
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}
}
