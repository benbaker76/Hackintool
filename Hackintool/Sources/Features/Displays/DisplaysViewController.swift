//
//  DisplaysViewController.swift
//  Hackintool
//
//  Displays section: connected displays, EDID fixes and HiDPI resolutions,
//  exported as a display override and an injector kext.
//

import Cocoa

final class DisplaysViewController: NSViewController, SectionContent {
	private var displays: [Display] = []
	private var settings: [String: DisplaySettings] = [:]

	private lazy var displayTable = DataTableViewController<Display>(columns: [
		DataColumn("Name", "Name", width: 200, onEdit: { [weak self] display, value in
			self?.update(display) { $0.name = value }
		}) { [unowned self] in self.settings(for: $0).name }
			.with(image: { [unowned self] in (self.settings(for: $0).isInternal ? Symbol.laptop : Symbol.desktop).image() }),
		DataColumn("VendorID", "Vendor ID", width: 80, monospaced: true, onEdit: { [weak self] display, value in
			guard let id = value.hexOrDecimalValue else { return }
			self?.update(display) { $0.vendorIDOverride = UInt32(truncatingIfNeeded: id) }
		}) { [unowned self] in String(format: "0x%04X", self.settings(for: $0).vendorIDOverride) },
		DataColumn("ProductID", "Product ID", width: 80, monospaced: true, onEdit: { [weak self] display, value in
			guard let id = value.hexOrDecimalValue else { return }
			self?.update(display) { $0.productIDOverride = UInt32(truncatingIfNeeded: id) }
		}) { [unowned self] in String(format: "0x%04X", self.settings(for: $0).productIDOverride) },
		DataColumn("SerialNumber", "Serial No.", width: 90, monospaced: true) { String(format: "0x%04X", $0.serialNumber) },
		// The framebuffer index on its GPU; it matches the connector row highlighted in Patch.
		DataColumn("Framebuffer", "FB", width: 40, monospaced: true, sortKey: { .number(Double($0.index)) }) { String($0.index) },
		DataColumn("Port", "Port", width: 50, monospaced: true) { String(format: "0x%02X", $0.port) },
		DataColumn("Internal", "Internal", width: 60) { [unowned self] in L(self.settings(for: $0).isInternal ? "Yes" : "No") },
		DataColumn("Aspect", "Aspect", width: 70) { $0.edid.flatMap(EDID.init)?.aspectRatio ?? "" },
	])

	private lazy var resolutionTable = DataTableViewController<IndexedResolution>(columns: [
		DataColumn("Width", "Width", width: 80, sortKey: { .number(Double($0.resolution.width)) }, onEdit: { [weak self] row, value in
			self?.updateResolution(row) { $0.width = Int(value) ?? $0.width }
		}) { String($0.resolution.width) },
		DataColumn("Height", "Height", width: 80, sortKey: { .number(Double($0.resolution.height)) }, onEdit: { [weak self] row, value in
			self?.updateResolution(row) { $0.height = Int(value) ?? $0.height }
		}) { String($0.resolution.height) },
		DataColumn("Type", "Type", width: 140) { $0.resolution.mode.title }
			.with(customView: { [unowned self] row in self.modePopUp(for: row) }),
	])

	private lazy var profilePopUp = ControlBar.popUp(EDIDProfile.allCases.map { $0.title }, target: self, action: #selector(optionChanged(_:)))
	private lazy var iconPopUp = ControlBar.popUp(["Default", "iMac", "MacBook", "MacBook Pro", "LG Display"].map(L), target: self, action: #selector(optionChanged(_:)))
	private lazy var presetPopUp = ControlBar.popUp(ResolutionPreset.allCases.map { L($0.title) }, target: self, action: #selector(optionChanged(_:)))
	private lazy var fixRangesCheckbox = Form.checkbox("Fix Monitor Ranges", target: self, action: #selector(optionChanged(_:)))
	private lazy var appleVIDCheckbox = Form.checkbox("Inject Apple VID", target: self, action: #selector(optionChanged(_:)))
	private lazy var applePIDCheckbox = Form.checkbox("Inject Apple PID", target: self, action: #selector(optionChanged(_:)))
	private lazy var rgbCheckbox = Form.checkbox("Force RGB Mode", target: self, action: #selector(optionChanged(_:)))
	private lazy var colorProfileCheckbox = Form.checkbox("Patch Color Profile", target: self, action: #selector(optionChanged(_:)))
	private lazy var internalCheckbox = Form.checkbox("Internal", target: self, action: #selector(optionChanged(_:)))
	private var optionControls: [NSControl] {
		return [profilePopUp, iconPopUp, presetPopUp, fixRangesCheckbox, appleVIDCheckbox, applePIDCheckbox, rgbCheckbox, colorProfileCheckbox, internalCheckbox]
	}

	override func loadView() {
		addChild(displayTable)
		addChild(resolutionTable)
		displayTable.tableView.allowsMultipleSelection = false
		displayTable.onSelectionChange = { [weak self] _ in self?.selectionChanged() }

		let options = Form.box("EDID", content: Form.grid([
			("EDID", profilePopUp),
			("Icon", iconPopUp),
			("Resolution", presetPopUp),
		]))
		let flags = NSStackView(views: [fixRangesCheckbox, appleVIDCheckbox, applePIDCheckbox, rgbCheckbox, colorProfileCheckbox, internalCheckbox])
		flags.orientation = .vertical
		flags.alignment = .leading
		flags.spacing = 6
		let patches = Form.box("Patch", content: flags)
		let settingsColumn = Form.scrollingStack([options, patches], spacing: 12, insets: NSEdgeInsets(all: 12))

		let resolutionsColumn = ControlBar.pane("Resolutions", symbol: .displays, content: resolutionTable.view, trailing: [
			ControlBar.iconButton(.add, toolTip: "Add", target: self, action: #selector(addResolutions(_:))),
			ControlBar.iconButton(.remove, toolTip: "Delete", target: self, action: #selector(deleteResolutions(_:))),
		])
		displayTable.emptyState = EmptyState(.displays, "No Displays", "No IODisplay services were found.")
		resolutionTable.emptyState = EmptyState(.displays, "No Custom Resolutions", "Pick a Resolution preset or press + to add HiDPI modes.")

		let bottom = NSSplitView()
		bottom.isVertical = true
		bottom.dividerStyle = .thin
		bottom.addArrangedSubview(ControlBar.pane("Override", symbol: .settings, content: settingsColumn))
		bottom.addArrangedSubview(resolutionsColumn)
		let settingsWidth = bottom.arrangedSubviews[0].widthAnchor.constraint(equalToConstant: 360)
		settingsWidth.priority = .defaultLow
		settingsWidth.isActive = true

		let footer = ControlBar.make([
			ControlBar.label("Exports a display override, an injector kext and EDID files for every display."),
		], trailing: [
			ControlBar.button("Export", symbol: .export, target: self, action: #selector(export(_:))),
		])

		let split = NSSplitView()
		split.isVertical = false
		split.dividerStyle = .thin
		split.addArrangedSubview(displayTable.view)
		split.addArrangedSubview(ControlBar.stack(header: nil, content: bottom, footer: footer))
		let tableHeight = displayTable.view.heightAnchor.constraint(equalToConstant: 140)
		tableHeight.priority = .defaultLow
		tableHeight.isActive = true
		view = split
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		refresh()
		NotificationCenter.default.addObserver(self, selector: #selector(screensChanged(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil)
	}

	@objc private func screensChanged(_ notification: Notification) {
		refresh()
	}

	// MARK: Settings per display

	private func key(_ display: Display) -> String {
		return "\(display.vendorID)-\(display.productID)-\(display.serialNumber)-\(display.index)"
	}

	private func settings(for display: Display) -> DisplaySettings {
		return settings[key(display)] ?? DisplaySettings(display: display)
	}

	private func update(_ display: Display, _ change: (inout DisplaySettings) -> Void) {
		var current = settings(for: display)
		change(&current)
		settings[key(display)] = current
		displayTable.reload()
	}

	private var selectedDisplay: Display? {
		return displayTable.selectedRows.first
	}

	private func selectionChanged() {
		let display = selectedDisplay
		optionControls.forEach { $0.isEnabled = display != nil }
		guard let display = display else {
			resolutionTable.setRows([])
			return
		}
		let current = settings(for: display)
		profilePopUp.selectItem(at: current.profile.rawValue)
		iconPopUp.selectItem(at: current.iconIndex)
		presetPopUp.selectItem(at: current.resolutionPreset.rawValue)
		let checkboxes: [(NSButton, Bool)] = [
			(fixRangesCheckbox, current.fixMonitorRanges), (appleVIDCheckbox, current.injectAppleVendorID),
			(applePIDCheckbox, current.injectAppleProductID), (rgbCheckbox, current.forceRGBMode),
			(colorProfileCheckbox, current.patchColorProfile), (internalCheckbox, current.isInternal),
		]
		checkboxes.forEach { $0.0.state = $0.1 ? .on : .off }
		reloadResolutions()
	}

	@objc private func optionChanged(_ sender: Any?) {
		guard let display = selectedDisplay else { return }
		update(display) { settings in
			settings.profile = EDIDProfile(rawValue: profilePopUp.indexOfSelectedItem) ?? .original
			settings.iconIndex = iconPopUp.indexOfSelectedItem
			settings.resolutionPreset = ResolutionPreset(rawValue: presetPopUp.indexOfSelectedItem) ?? .p1080
			settings.fixMonitorRanges = fixRangesCheckbox.state == .on
			settings.injectAppleVendorID = appleVIDCheckbox.state == .on
			settings.injectAppleProductID = applePIDCheckbox.state == .on
			settings.forceRGBMode = rgbCheckbox.state == .on
			settings.patchColorProfile = colorProfileCheckbox.state == .on
			settings.isInternal = internalCheckbox.state == .on
		}
	}

	// MARK: Resolutions

	/// A resolution with its position, so edits can find it again.
	struct IndexedResolution {
		let index: Int
		let resolution: ScaledResolution
	}

	private func reloadResolutions() {
		let list = selectedDisplay.map { settings(for: $0).resolutions } ?? []
		resolutionTable.setRows(list.enumerated().map { IndexedResolution(index: $0.offset, resolution: $0.element) })
	}

	private func updateResolution(_ row: IndexedResolution, _ change: (inout ScaledResolution) -> Void) {
		guard let display = selectedDisplay else { return }
		update(display) { settings in
			guard settings.resolutions.indices.contains(row.index) else { return }
			change(&settings.resolutions[row.index])
		}
		reloadResolutions()
	}

	private func modePopUp(for row: IndexedResolution) -> NSView {
		let popUp = ResolutionModePopUp(row: row, target: self, action: #selector(modeChanged(_:)))
		popUp.controlSize = .small
		popUp.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		popUp.isBordered = false
		return popUp
	}

	@objc private func modeChanged(_ sender: ResolutionModePopUp) {
		updateResolution(sender.row) { $0.mode = HiDPIMode(rawValue: sender.indexOfSelectedItem) ?? .auto }
	}

	/// Fills an empty list from the resolution preset, otherwise adds one editable entry.
	@objc private func addResolutions(_ sender: Any?) {
		guard let display = selectedDisplay else { return }
		update(display) { settings in
			if settings.resolutions.isEmpty && settings.resolutionPreset != .manual {
				settings.resolutions = ScaledResolution.preset(settings.resolutionPreset)
			} else {
				settings.resolutions.append(ScaledResolution(width: 1920, height: 1080, mode: .auto))
			}
		}
		reloadResolutions()
	}

	@objc private func deleteResolutions(_ sender: Any?) {
		guard let display = selectedDisplay else { return }
		let indices = Set(resolutionTable.targetRows.map { $0.index })
		update(display) { settings in
			settings.resolutions = settings.resolutions.enumerated().filter { !indices.contains($0.offset) }.map { $0.element }
		}
		reloadResolutions()
	}

	// MARK: SectionContent

	var canRefresh: Bool { return true }

	func refresh() {
		displays = Display.all()
		displayTable.setRows(displays)
		if !displays.isEmpty && displayTable.tableView.selectedRow < 0 {
			displayTable.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		}
		selectionChanged()
	}

	var searchPlaceholder: String? { return displayTable.searchPlaceholder }
	func search(_ text: String) { displayTable.search(text) }

	// MARK: Export

	@objc private func export(_ sender: Any?) {
		let entries = displays.map { ($0, settings(for: $0)) }
		guard !entries.isEmpty else { return }
		FilePanels.chooseFolder(prompt: "Export") { folder in
			var written: [URL] = []
			for (display, settings) in entries {
				do {
					written += try DisplayOverride.export(display: display, settings: settings, to: folder)
				} catch {
					Alerts.error(L("Couldn't export %@", settings.name), error.localizedDescription)
				}
			}
			if let icons = DisplayOverride.exportIcons(entries, to: folder) {
				written.append(icons)
			}
			NSWorkspace.shared.activateFileViewerSelecting(written)
			// /System is read-only on macOS 11+; overrides go in /Library instead.
			Alerts.show("Display Overrides Exported",
			            L("Copy the DisplayVendorID-… folders and Icons.plist to /Library/Displays/Contents/Resources/Overrides, or install DisplayEDID-….kext with your bootloader, then restart."))
		}
	}
}

final class ResolutionModePopUp: NSPopUpButton {
	let row: DisplaysViewController.IndexedResolution

	init(row: DisplaysViewController.IndexedResolution, target: AnyObject, action: Selector) {
		self.row = row
		super.init(frame: .zero, pullsDown: false)
		addItems(withTitles: HiDPIMode.allCases.map { L($0.title) })
		for (item, mode) in zip(itemArray, HiDPIMode.allCases) {
			item.toolTip = mode.detail
		}
		selectItem(at: row.resolution.mode.rawValue)
		toolTip = row.resolution.mode.detail
		self.target = target
		self.action = action
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}
}
