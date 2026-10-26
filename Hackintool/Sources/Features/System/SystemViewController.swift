//
//  SystemViewController.swift
//  Hackintool
//
//  System section: system info, serial generator, Mac model database and peripherals.
//

import Cocoa

final class SystemViewController: TabbedViewController {
	init() {
		super.init(identifier: "System", pages: [
			Page(title: L("System"), viewController: SystemInfoViewController()),
			Page(title: L("Serial"), viewController: SerialGeneratorViewController()),
			Page(title: L("Model"), viewController: ModelInfoViewController()),
			Page(title: L("Peripherals"), viewController: PeripheralsViewController()),
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}
}

/// System ▸ System: everything about this machine, grouped.
final class SystemInfoViewController: PropertyListViewController {
	override func viewDidLoad() {
		super.viewDidLoad()
		onRefresh = { [weak self] in self?.load() }
		load()
	}

	private func load() {
		// The VDA decoder probe and registry walks take a moment; keep the UI responsive.
		DispatchQueue.global(qos: .userInitiated).async {
			let groups = SystemReport.groups(pciDevices: PCIDevice.all(), displays: Display.all())
			DispatchQueue.main.async { self.setGroups(groups) }
		}
	}
}

/// System ▸ Serial: generate a serial, board serial and SmUUID for a Mac model.
final class SerialGeneratorViewController: NSViewController, SectionContent {
	private let list = PropertyListViewController(showsGroupHeaders: false)
	private lazy var modelPopUp = ControlBar.popUp(MacSerial.modelIdentifiers, target: self, action: #selector(generate(_:)))
	private var generated: MacSerial.Generated?

	override func loadView() {
		addChild(list)
		let header = ControlBar.make([
			ControlBar.label("Model"),
			modelPopUp,
			ControlBar.iconButton(.system, toolTip: "Go to current model", target: self, action: #selector(selectCurrentModel(_:))),
			ControlBar.iconButton(.refresh, toolTip: "Generate", target: self, action: #selector(generate(_:))),
		], trailing: [
			ControlBar.button("EveryMac", symbol: .web, target: self, action: #selector(checkOnEveryMac(_:))),
			ControlBar.button("Apple Coverage", symbol: .web, target: self, action: #selector(checkCoverage(_:))),
		])
		view = ControlBar.stack(header: header, content: list.view)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		selectCurrentModel(nil)
	}

	@objc private func selectCurrentModel(_ sender: Any?) {
		if let model = Machine.shared.modelIdentifier, modelPopUp.itemTitles.contains(model) {
			modelPopUp.selectItem(withTitle: model)
		}
		generate(nil)
	}

	@objc private func generate(_ sender: Any?) {
		guard let model = modelPopUp.titleOfSelectedItem, let generated = MacSerial.generate(modelIdentifier: model) else { return }
		self.generated = generated
		list.setItems([
			PropertyItem("Serial Number", generated.serialNumber),
			PropertyItem("Board Serial Number", generated.boardSerialNumber),
			PropertyItem("SmUUID", generated.smUUID),
		] + SystemReport.serialItems(MacSerial.decode(generated.serialNumber)))
	}

	@objc private func checkOnEveryMac(_ sender: Any?) {
		open("https://everymac.com/ultimate-mac-lookup/?search_keywords=")
	}

	@objc private func checkCoverage(_ sender: Any?) {
		open("https://checkcoverage.apple.com/us/en/?sn=")
	}

	private func open(_ prefix: String) {
		guard let serial = generated?.serialNumber, let url = URL(string: prefix + serial) else { return }
		NSWorkspace.shared.open(url)
	}

	var canRefresh: Bool { return true }
	func refresh() { generate(nil) }
	var searchPlaceholder: String? { return list.searchPlaceholder }
	func search(_ text: String) { list.search(text) }
}

/// System ▸ Model: specifications of Mac models from EveryMac.
final class ModelInfoViewController: NSViewController, SectionContent {
	private let list = PropertyListViewController(showsGroupHeaders: false)
	private let systems = BundledData.systems
	private lazy var modelPopUp: NSPopUpButton = {
		let titles = systems.map { "\($0["Name"] as? String ?? "?") (\($0["Model ID"] as? String ?? "?"))" }
		return ControlBar.popUp(titles, target: self, action: #selector(modelChanged(_:)))
	}()

	override func loadView() {
		addChild(list)
		let header = ControlBar.make([ControlBar.label("Model"), modelPopUp])
		view = ControlBar.stack(header: header, content: list.view)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		if let current = Machine.shared.modelIdentifier,
		   let index = systems.firstIndex(where: { $0["Model ID"] as? String == current }) {
			modelPopUp.selectItem(at: index)
		}
		modelChanged(nil)
	}

	@objc private func modelChanged(_ sender: Any?) {
		let index = modelPopUp.indexOfSelectedItem
		guard systems.indices.contains(index) else { return }
		let system = systems[index]
		list.setItems(system.keys.sorted().map { PropertyItem($0, String(describing: system[$0]!)) })
	}

	var searchPlaceholder: String? { return list.searchPlaceholder }
	func search(_ text: String) { list.search(text) }
}
