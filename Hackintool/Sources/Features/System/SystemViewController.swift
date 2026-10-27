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

/// System ▸ System: a summary card, then everything about this machine, grouped.
final class SystemInfoViewController: PropertyListViewController {
	private let card = MachineCardView()

	override func loadView() {
		super.loadView()
		view = ControlBar.stack(header: card, content: view)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		onRefresh = { [weak self] in self?.load() }
		load()
	}

	private func load() {
		// The VDA decoder probe and registry walks take a moment; keep the UI responsive.
		DispatchQueue.global(qos: .userInitiated).async {
			let pciDevices = PCIDevice.all()
			let groups = SystemReport.groups(pciDevices: pciDevices, displays: Display.all())
			let summary = MachineCardView.Summary(pciDevices: pciDevices)
			DispatchQueue.main.async {
				self.card.show(summary)
				self.setGroups(groups)
			}
		}
	}
}

/// The Mac's icon and name with its OS, CPU, memory, graphics and bootloader, like About This Mac.
final class MachineCardView: NSView {
	struct Summary {
		let title: String
		let subtitle: String
		let details: String
		let bootloader: String?

		init(pciDevices: [PCIDevice]) {
			let model = Machine.shared.modelIdentifier
			let marketingName = model.flatMap { model in BundledData.systems.first { $0["Model ID"] as? String == model }?["Name"] as? String }
			// EveryMac names start with "Apple ", e.g. Apple iMac "Core i7" 3.8 27" (5K, 2020).
			title = marketingName.map { $0.hasPrefix("Apple ") ? String($0.dropFirst(6)) : $0 } ?? model ?? L("Unknown Mac")
			let version = ProcessInfo.processInfo.operatingSystemVersion
			var os = SystemInfo.osName
			// "macOS Tahoe Version 26.1 (Build 25B78)" → "macOS Tahoe 26.1 (25B78)".
			os = os.replacingOccurrences(of: "Version ", with: "").replacingOccurrences(of: "Build ", with: "")
			if os.isEmpty {
				os = "macOS \(version.majorVersion).\(version.minorVersion)"
			}
			subtitle = [model, os].compactMap { $0 }.joined(separator: "  ·  ")
			// "Intel(R) Core(TM) i9-10900K CPU @ 3.70GHz" → "Intel Core i9-10900K @ 3.70GHz".
			let cpu = SystemInfo.cpu.replacingOccurrences(of: "(R)", with: "").replacingOccurrences(of: "(TM)", with: "")
				.replacingOccurrences(of: " CPU", with: "").replacingOccurrences(of: "  ", with: " ")
			let memory = SystemInfo.memorySize.replacingOccurrences(of: ".00", with: "")
			let gpus = pciDevices.filter { $0.isDisplay }.map { device -> String in
				// pci.ids names look like "Navi 23 [Radeon RX 6600/6600 XT/6600M]"; the model property is friendlier.
				device.model ?? device.deviceName
			}
			details = ([cpu, memory] + gpus).filter { $0 != "???" }.joined(separator: "  ·  ")
			switch Bootloader.detected {
			case .openCore(let version)?: bootloader = "OpenCore \(version)"
			case .clover(let revision, _)?: bootloader = "Clover r\(revision)"
			case nil: bootloader = nil
			}
		}
	}

	private let iconView = NSImageView()
	private let titleLabel = NSTextField(labelWithString: "")
	private let subtitleLabel = NSTextField(labelWithString: "")
	private let detailsLabel = NSTextField(labelWithString: "")
	private let badgeContainer = NSStackView()

	init() {
		super.init(frame: .zero)
		#if DEBUG
		let sample = SampleData.isEnabled
		#else
		let sample = false
		#endif
		// This Mac's own icon (it follows the SMBIOS model); the sample machine isn't this Mac.
		iconView.image = sample ? Symbol.iMac.image(size: 64) : NSImage(named: NSImage.computerName)
		iconView.contentTintColor = .controlAccentColor
		iconView.imageScaling = .scaleProportionallyUpOrDown
		titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
		subtitleLabel.textColor = .secondaryLabelColor
		detailsLabel.textColor = .secondaryLabelColor
		for label in [titleLabel, subtitleLabel, detailsLabel] {
			label.lineBreakMode = .byTruncatingTail
			label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		}

		let text = NSStackView(views: [titleLabel, subtitleLabel, detailsLabel])
		text.orientation = .vertical
		text.alignment = .leading
		text.spacing = 3
		let row = NSStackView(views: [iconView, text, badgeContainer])
		row.alignment = .centerY
		row.spacing = 14
		row.setHuggingPriority(.defaultLow, for: .horizontal)
		text.setHuggingPriority(.defaultLow, for: .horizontal)
		addPinnedSubview(row, insets: NSEdgeInsets(top: 16, left: 20, bottom: 14, right: 20))
		NSLayoutConstraint.activate([
			iconView.widthAnchor.constraint(equalToConstant: 64),
			iconView.heightAnchor.constraint(equalToConstant: 64),
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	func show(_ summary: Summary) {
		titleLabel.stringValue = summary.title
		subtitleLabel.stringValue = summary.subtitle
		detailsLabel.stringValue = summary.details
		detailsLabel.toolTip = summary.details
		badgeContainer.setViews(summary.bootloader.map { [StatusBadge.make($0, color: .systemBlue, symbol: .boot)] } ?? [], in: .trailing)
		badgeContainer.views.forEach { $0.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true; $0.heightAnchor.constraint(equalToConstant: 22).isActive = true }
	}

	override func draw(_ dirtyRect: NSRect) {
		NSColor.separatorColor.setFill()
		NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
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
