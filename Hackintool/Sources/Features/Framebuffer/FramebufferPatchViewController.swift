//
//  FramebufferPatchViewController.swift
//  Hackintool
//
//  Patch ▸ Patch: what to patch and how, and the generated output.
//

import Cocoa

final class FramebufferPatchViewController: NSViewController, SectionContent {
	private let model: FramebufferModel
	private let output = ScrollingTextView(monospaced: true, wraps: false)

	/// Boolean options: title, tooltip identifier, setting, and whether it changes the auto patches.
	private struct Option {
		let title: String
		let identifier: String
		let setting: ReferenceWritableKeyPath<SettingsProxy, Bool>
		let affectsPatches: Bool
	}

	private static let generalOptions: [Option] = [
		Option(title: "Auto Detect Changes", identifier: "AutoDetectChanges", setting: \.autoDetectChanges, affectsPatches: false),
		Option(title: "Use All Data Method", identifier: "UseAllDataMethod", setting: \.useAllDataMethod, affectsPatches: false),
		Option(title: "All", identifier: "PatchAll", setting: \.patchAll, affectsPatches: false),
		Option(title: "Connectors", identifier: "PatchConnectors", setting: \.patchConnectors, affectsPatches: false),
		Option(title: "VRAM", identifier: "PatchVRAM", setting: \.patchVRAM, affectsPatches: false),
		Option(title: "Graphics Device", identifier: "PatchGraphicDevice", setting: \.patchGraphicDevice, affectsPatches: false),
		Option(title: "Audio Device", identifier: "PatchAudioDevice", setting: \.patchAudioDevice, affectsPatches: false),
		Option(title: "PCI Devices", identifier: "PatchPCIDevices", setting: \.patchPCIDevices, affectsPatches: false),
		Option(title: "EDID", identifier: "PatchEDID", setting: \.patchEDID, affectsPatches: false),
	]

	private static let advancedOptions: [Option] = [
		Option(title: "DVMT Pre-alloc 32 MB", identifier: "DVMTPrealloc32MB", setting: \.dvmtPrealloc32MB, affectsPatches: true),
		Option(title: "VRAM 2048 MB", identifier: "VRAM2048MB", setting: \.vram2048MB, affectsPatches: true),
		Option(title: "Disable eGPU", identifier: "DisableeGPU", setting: \.disableeGPU, affectsPatches: false),
		Option(title: "Enable HDMI 2.0", identifier: "EnableHDMI20", setting: \.enableHDMI20, affectsPatches: false),
		Option(title: "DP → HDMI", identifier: "DPtoHDMI", setting: \.dpToHDMI, affectsPatches: true),
		Option(title: "Use Intel HDMI", identifier: "UseIntelHDMI", setting: \.useIntelHDMI, affectsPatches: false),
		Option(title: "GFX Y-Tile Fix", identifier: "GfxYTileFix", setting: \.gfxYTileFix, affectsPatches: false),
		Option(title: "Hotplug Reboot Fix", identifier: "HotplugRebootFix", setting: \.hotplugRebootFix, affectsPatches: true),
		Option(title: "HDMI Infinite Loop Fix", identifier: "HDMIInfiniteLoopFix", setting: \.hdmiInfiniteLoopFix, affectsPatches: false),
		Option(title: "Spoof Audio Device ID", identifier: "SpoofAudioDeviceID", setting: \.spoofAudioDeviceID, affectsPatches: false),
		Option(title: "Inject Fake IGPU", identifier: "InjectFakeIGPU", setting: \.injectFakeIGPU, affectsPatches: false),
		Option(title: "USB Port Limit Patch", identifier: "USBPortLimit", setting: \.usbPortLimit, affectsPatches: false),
	]

	private enum Method: Int, CaseIterable {
		case kextsToPatchHex, kextsToPatchBase64, deviceProperties, iASLDSL

		var title: String {
			switch self {
			case .kextsToPatchHex: return "KextsToPatch (Hex)"
			case .kextsToPatchBase64: return "KextsToPatch (Base64)"
			case .deviceProperties: return "DeviceProperties"
			case .iASLDSL: return "iASL DSL Source"
			}
		}

		static var current: Method {
			if Settings.kextsToPatchHex { return .kextsToPatchHex }
			if Settings.kextsToPatchBase64 { return .kextsToPatchBase64 }
			if Settings.iASLDSLSource { return .iASLDSL }
			return .deviceProperties
		}

		func makeCurrent() {
			Settings.kextsToPatchHex = self == .kextsToPatchHex
			Settings.kextsToPatchBase64 = self == .kextsToPatchBase64
			Settings.deviceProperties = self == .deviceProperties
			Settings.iASLDSLSource = self == .iASLDSL
		}
	}

	private let settings = SettingsProxy()
	private var checkboxes: [(NSButton, Option)] = []
	private lazy var methodPopUp = ControlBar.popUp(Method.allCases.map { $0.title }, target: self, action: #selector(methodChanged(_:)))
	private lazy var bootloaderPopUp = ControlBar.popUp(["Auto Detect", "Clover", "OpenCore"], target: self, action: #selector(bootloaderChanged(_:)))
	private lazy var dpcdCheckbox = Form.checkbox("DPCD Max Link Rate", identifier: "DPCDMaxLinkRateFix", target: self, action: #selector(dpcdChanged(_:)))
	private lazy var dpcdPopUp = ControlBar.popUp(["RBR", "HBR", "HBR2", "HBR3"], target: self, action: #selector(dpcdChanged(_:)))
	private lazy var portLimitCheckbox = Form.checkbox("FB Port Limit", identifier: "FBPortLimit", target: self, action: #selector(portLimitChanged(_:)))
	private lazy var portLimitPopUp = ControlBar.popUp(["1", "2", "3"], target: self, action: #selector(portLimitChanged(_:)))
	private lazy var deviceIDCheckbox = Form.checkbox("Inject Device ID", identifier: "InjectDeviceID", target: self, action: #selector(deviceIDChanged(_:)))
	private lazy var deviceIDPopUp = ControlBar.popUp([], target: self, action: #selector(deviceIDChanged(_:)))
	private lazy var lspconCheckbox = Form.checkbox("Enable Driver", identifier: "LSPCON_Enable", target: self, action: #selector(lspconChanged(_:)))
	private lazy var lspconAutoDetectCheckbox = Form.checkbox("Auto Detect", identifier: "LSPCON_AutoDetect", target: self, action: #selector(lspconChanged(_:)))
	private lazy var lspconConnectorCheckbox = Form.checkbox("Connector", identifier: "LSPCON_Connector", target: self, action: #selector(lspconChanged(_:)))
	private lazy var lspconConnectorPopUp = ControlBar.popUp(["0", "1", "2", "3"], target: self, action: #selector(lspconChanged(_:)))
	private lazy var lspconModeCheckbox = Form.checkbox("Preferred Mode", identifier: "LSPCON_PreferredMode", target: self, action: #selector(lspconChanged(_:)))
	private lazy var lspconModePopUp = ControlBar.popUp(["LS (DP to HDMI 1.4)", "PCON (DP to HDMI 2.0)"], target: self, action: #selector(lspconChanged(_:)))

	init(model: FramebufferModel) {
		self.model = model
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	override func loadView() {
		func checkboxColumns(_ options: [Option], columns: Int) -> NSView {
			let buttons = options.map { option -> NSButton in
				let button = Form.checkbox(option.title, identifier: option.identifier, target: self, action: #selector(optionChanged(_:)))
				checkboxes.append((button, option))
				return button
			}
			let rows = stride(from: 0, to: buttons.count, by: columns).map { Array(buttons[$0..<min($0 + columns, buttons.count)]) }
			let grid = NSGridView(views: rows.map { row in row + Array(repeating: NSGridCell.emptyContentView, count: columns - row.count) })
			grid.rowSpacing = 6
			grid.columnSpacing = 16
			// Keep the columns at their natural width when the box is wider than the grid.
			let container = NSStackView(views: [grid])
			container.orientation = .vertical
			container.alignment = .leading
			return container
		}
		func row(_ views: [NSView]) -> NSStackView {
			let stack = NSStackView(views: views)
			stack.orientation = .horizontal
			stack.spacing = 8
			return stack
		}
		for popUp in [dpcdPopUp, portLimitPopUp, deviceIDPopUp, lspconConnectorPopUp, lspconModePopUp] {
			popUp.controlSize = .small
			popUp.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		}

		let general = Form.box("General", content: checkboxColumns(FramebufferPatchViewController.generalOptions, columns: 3))
		let advancedGrid = checkboxColumns(FramebufferPatchViewController.advancedOptions, columns: 3)
		let advancedStack = NSStackView(views: [
			advancedGrid,
			row([dpcdCheckbox, dpcdPopUp, portLimitCheckbox, portLimitPopUp, deviceIDCheckbox, deviceIDPopUp]),
		])
		advancedStack.orientation = .vertical
		advancedStack.alignment = .leading
		advancedStack.spacing = 10
		let advanced = Form.box("Advanced", content: advancedStack)
		let lspconStack = NSStackView(views: [
			row([lspconCheckbox, lspconAutoDetectCheckbox]),
			row([lspconConnectorCheckbox, lspconConnectorPopUp, lspconModeCheckbox, lspconModePopUp]),
		])
		lspconStack.orientation = .vertical
		lspconStack.alignment = .leading
		lspconStack.spacing = 8
		let lspcon = Form.box("LSPCON", content: lspconStack)
		let options = Form.scrollingStack([general, advanced, lspcon], spacing: 12, insets: NSEdgeInsets(all: 16))

		let header = ControlBar.make([
			ControlBar.label("Method"), methodPopUp,
			ControlBar.label("Bootloader"), bootloaderPopUp,
		], trailing: [
			ControlBar.button("Generate Patch", symbol: .refresh, target: self, action: #selector(generate(_:))),
			ControlBar.iconButton(.copy, toolTip: "Copy", target: self, action: #selector(copyOutput(_:))),
			ControlBar.button("Save to config.plist…", symbol: .export, target: self, action: #selector(saveToConfig(_:))),
		])

		let split = NSSplitView()
		split.isVertical = false
		split.dividerStyle = .thin
		split.addArrangedSubview(options)
		split.addArrangedSubview(output.scrollView)
		let top = options.heightAnchor.constraint(equalTo: split.heightAnchor, multiplier: 0.5)
		top.priority = .defaultLow
		top.isActive = true

		view = ControlBar.stack(header: header, content: split)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		model.observe { [weak self] in
			self?.updateDeviceIDs()
			self?.generate(nil)
		}
		updateControls()
		updateDeviceIDs()
	}

	override func viewWillAppear() {
		super.viewWillAppear()
		generate(nil)
	}

	private func updateControls() {
		for (button, option) in checkboxes {
			button.state = settings[keyPath: option.setting] ? .on : .off
		}
		methodPopUp.selectItem(at: Method.current.rawValue)
		bootloaderPopUp.selectItem(at: Settings.selectedBootloader.rawValue)
		dpcdCheckbox.state = Settings.dpcdMaxLinkRateFix ? .on : .off
		dpcdPopUp.selectItem(at: Settings.dpcdMaxLinkRate.clamped(to: 0...3))
		portLimitCheckbox.state = Settings.fbPortLimit ? .on : .off
		portLimitPopUp.selectItem(at: Settings.fbPortCount.clamped(to: 1...3) - 1)
		deviceIDCheckbox.state = Settings.injectDeviceID ? .on : .off
		lspconCheckbox.state = Settings.lspconEnable ? .on : .off
		lspconAutoDetectCheckbox.state = Settings.lspconAutoDetect ? .on : .off
		lspconConnectorCheckbox.state = Settings.lspconConnector ? .on : .off
		lspconConnectorPopUp.selectItem(at: Settings.lspconConnectorIndex.clamped(to: 0...3))
		lspconModeCheckbox.state = Settings.lspconPreferredMode ? .on : .off
		lspconModePopUp.selectItem(at: Settings.lspconPreferredModeIndex.clamped(to: 0...1))
		dpcdPopUp.isEnabled = Settings.dpcdMaxLinkRateFix
		portLimitPopUp.isEnabled = Settings.fbPortLimit
		deviceIDPopUp.isEnabled = Settings.injectDeviceID
		let lspconOn = Settings.lspconEnable
		[lspconAutoDetectCheckbox, lspconConnectorCheckbox, lspconModeCheckbox].forEach { $0.isEnabled = lspconOn }
		lspconConnectorPopUp.isEnabled = lspconOn && Settings.lspconConnector
		lspconModePopUp.isEnabled = lspconOn && Settings.lspconPreferredMode
	}

	private func updateDeviceIDs() {
		deviceIDPopUp.removeAllItems()
		for id in model.deviceIDs {
			let name = BundledData.intelGPUs[String(format: "0x%04X", id)] as? String
			deviceIDPopUp.addItem(withTitle: String(format: "0x%04X", id) + (name.map { " — \($0)" } ?? ""))
		}
		if deviceIDPopUp.numberOfItems > 0 {
			deviceIDPopUp.selectItem(at: min(model.injectedDeviceIndex, deviceIDPopUp.numberOfItems - 1))
		}
	}

	// MARK: Actions

	@objc private func optionChanged(_ sender: NSButton) {
		guard let option = checkboxes.first(where: { $0.0 === sender })?.1 else { return }
		settings[keyPath: option.setting] = sender.state == .on
		if option.affectsPatches {
			model.settingsChanged()
		} else {
			generate(nil)
		}
	}

	@objc private func methodChanged(_ sender: NSPopUpButton) {
		Method(rawValue: sender.indexOfSelectedItem)?.makeCurrent()
		generate(nil)
	}

	@objc private func bootloaderChanged(_ sender: NSPopUpButton) {
		Settings.selectedBootloader = BootloaderChoice(rawValue: sender.indexOfSelectedItem) ?? .autoDetect
		generate(nil)
	}

	@objc private func dpcdChanged(_ sender: Any?) {
		Settings.dpcdMaxLinkRateFix = dpcdCheckbox.state == .on
		Settings.dpcdMaxLinkRate = max(dpcdPopUp.indexOfSelectedItem, 0)
		updateControls()
		model.settingsChanged()
	}

	@objc private func portLimitChanged(_ sender: Any?) {
		Settings.fbPortLimit = portLimitCheckbox.state == .on
		Settings.fbPortCount = max(portLimitPopUp.indexOfSelectedItem, 0) + 1
		updateControls()
		model.settingsChanged()
	}

	@objc private func deviceIDChanged(_ sender: Any?) {
		Settings.injectDeviceID = deviceIDCheckbox.state == .on
		model.injectedDeviceIndex = max(deviceIDPopUp.indexOfSelectedItem, 0)
		updateControls()
		generate(nil)
	}

	@objc private func lspconChanged(_ sender: Any?) {
		Settings.lspconEnable = lspconCheckbox.state == .on
		Settings.lspconAutoDetect = lspconAutoDetectCheckbox.state == .on
		Settings.lspconConnector = lspconConnectorCheckbox.state == .on
		Settings.lspconConnectorIndex = max(lspconConnectorPopUp.indexOfSelectedItem, 0)
		Settings.lspconPreferredMode = lspconModeCheckbox.state == .on
		Settings.lspconPreferredModeIndex = max(lspconModePopUp.indexOfSelectedItem, 0)
		updateControls()
		generate(nil)
	}

	// MARK: Output

	@objc private func generate(_ sender: Any?) {
		output.clear()
		guard let context = model.context else { return }
		output.append(FramebufferPatchViewController.patchText(context: context, method: Method.current))
		output.textView.scrollToBeginningOfDocument(nil)
	}

	private static func patchText(context: PatchContext, method: Method) -> String {
		switch method {
		case .kextsToPatchHex:
			return FramebufferPatcher.kextsToPatch(context: context, format: .hex)
		case .kextsToPatchBase64:
			return FramebufferPatcher.kextsToPatch(context: context, format: .base64)
		case .iASLDSL:
			return FramebufferPatcher.ssdt(context: context)
		case .deviceProperties:
			return makeConfig(context: context, format: BootloaderConfigFormat.current).xmlString
		}
	}

	/// The DeviceProperties (and USB port limit patches) as a config.plist fragment.
	private static func makeConfig(context: PatchContext, format: BootloaderConfigFormat, into config: ConfigPlist? = nil) -> ConfigPlist {
		let config = config ?? ConfigPlist(format: format)
		FramebufferPatcher.addDeviceProperties(to: config, context: context)
		if Settings.usbPortLimit {
			let usb = (BundledData.plist("config_patches", in: "USB") as? [String: Any])?["KernelAndKextPatches"] as? [String: Any]
			for patch in usb?["KextsToPatch"] as? [[String: Any]] ?? [] where ConfigPlist.matchesCurrentOS(patch["MatchOS"] as? String) {
				config.addKernelPatch(fromClover: patch)
			}
		}
		return config
	}

	@objc private func copyOutput(_ sender: Any?) {
		Pasteboard.copy(output.textView.string)
	}

	@objc private func saveToConfig(_ sender: Any?) {
		FramebufferPatchViewController.saveToConfig(model: model)
	}

	static func saveToConfig(model: FramebufferModel) {
		guard let context = model.context else { return }
		ConfigPlistPicker.choose { config, url in
			_ = makeConfig(context: context, format: config.format, into: config)
			do {
				try config.write(to: url)
				Alerts.show("Patch Success!", url.path)
			} catch {
				Alerts.error("Couldn't write the config.plist.", error.localizedDescription)
			}
		}
	}

	var canRefresh: Bool { return true }
	func refresh() { generate(nil) }
}

/// Key paths to the boolean patch settings, so the option tables can bind to them.
final class SettingsProxy {
	var autoDetectChanges: Bool { get { Settings.autoDetectChanges } set { Settings.autoDetectChanges = newValue } }
	var useAllDataMethod: Bool { get { Settings.useAllDataMethod } set { Settings.useAllDataMethod = newValue } }
	var patchAll: Bool { get { Settings.patchAll } set { Settings.patchAll = newValue } }
	var patchConnectors: Bool { get { Settings.patchConnectors } set { Settings.patchConnectors = newValue } }
	var patchVRAM: Bool { get { Settings.patchVRAM } set { Settings.patchVRAM = newValue } }
	var patchGraphicDevice: Bool { get { Settings.patchGraphicDevice } set { Settings.patchGraphicDevice = newValue } }
	var patchAudioDevice: Bool { get { Settings.patchAudioDevice } set { Settings.patchAudioDevice = newValue } }
	var patchPCIDevices: Bool { get { Settings.patchPCIDevices } set { Settings.patchPCIDevices = newValue } }
	var patchEDID: Bool { get { Settings.patchEDID } set { Settings.patchEDID = newValue } }
	var dvmtPrealloc32MB: Bool { get { Settings.dvmtPrealloc32MB } set { Settings.dvmtPrealloc32MB = newValue } }
	var vram2048MB: Bool { get { Settings.vram2048MB } set { Settings.vram2048MB = newValue } }
	var disableeGPU: Bool { get { Settings.disableeGPU } set { Settings.disableeGPU = newValue } }
	var enableHDMI20: Bool { get { Settings.enableHDMI20 } set { Settings.enableHDMI20 = newValue } }
	var dpToHDMI: Bool { get { Settings.dpToHDMI } set { Settings.dpToHDMI = newValue } }
	var useIntelHDMI: Bool { get { Settings.useIntelHDMI } set { Settings.useIntelHDMI = newValue } }
	var gfxYTileFix: Bool { get { Settings.gfxYTileFix } set { Settings.gfxYTileFix = newValue } }
	var hotplugRebootFix: Bool { get { Settings.hotplugRebootFix } set { Settings.hotplugRebootFix = newValue } }
	var hdmiInfiniteLoopFix: Bool { get { Settings.hdmiInfiniteLoopFix } set { Settings.hdmiInfiniteLoopFix = newValue } }
	var spoofAudioDeviceID: Bool { get { Settings.spoofAudioDeviceID } set { Settings.spoofAudioDeviceID = newValue } }
	var injectFakeIGPU: Bool { get { Settings.injectFakeIGPU } set { Settings.injectFakeIGPU = newValue } }
	var usbPortLimit: Bool { get { Settings.usbPortLimit } set { Settings.usbPortLimit = newValue } }
}
