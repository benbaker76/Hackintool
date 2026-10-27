//
//  RadeonViewController.swift
//  Hackintool
//
//  Radeon section (experimental): identify an AMD GPU, see whether macOS supports it,
//  and generate the WhateverGreen device properties and boot-args for it.
//

import Cocoa

final class RadeonViewController: NSViewController, SectionContent, NSTextFieldDelegate {
	private struct Toggle {
		let title: String
		let detail: String
		let option: WritableKeyPath<RadeonOptions, Bool>
	}

	private static let propertyToggles: [Toggle] = [
		Toggle(title: "Disable GPU (disable-gpu)", detail: "Stops macOS using this GPU, for cards it has no driver for.", option: \.disableGPU),
		Toggle(title: "agdpmod=pikera", detail: "Replaces board-id with board-ix so AppleGraphicsDevicePolicy doesn't black-screen Navi cards with iMacPro1,1/MacPro7,1.", option: \.agdpmodPikera),
		Toggle(title: "unfairgva", detail: "Lets the hardware DRM decoder work on CPUs macOS considers too old (unfairgva bit 1).", option: \.unfairgva),
		Toggle(title: "enable-gva-support", detail: "Turns on AMD hardware video decoding where macOS leaves it off.", option: \.enableGvaSupport),
		Toggle(title: "Force_Load_FalconSMUFW", detail: "Force-loads the SMU firmware on X5000 (Vega) and newer cards without Apple firmware.", option: \.forceSMUFirmware),
		Toggle(title: "CFG_USE_AGDC off", detail: "Can fix 4K-and-lower DisplayPort displays that don't wake.", option: \.disableAGDC),
	]

	private static let bootArgToggles: [Toggle] = [
		Toggle(title: "-raddvi", detail: "DVI transmitter correction, needed by 290X, 370 and similar cards.", option: \.radDVI),
		Toggle(title: "radpg=15", detail: "Disables power-gating modes; needed by Cape Verde (HD 7730/7750/7770, R7 250/250X).", option: \.radPG15),
		Toggle(title: "-rad24", detail: "Forces 24-bit output for displays that show distorted, blinking colours.", option: \.rad24),
		Toggle(title: "-radcodec", detail: "Uses the spoofed device ID in AMDRadeonVADriver so unsupported cards get the hardware encoder.", option: \.radCodec),
		Toggle(title: "-radvesa", detail: "Turns off AMD acceleration completely (troubleshooting only).", option: \.radVESA),
		Toggle(title: "applbkl=3", detail: "PWM backlight for a laptop panel wired to an RX 5000 GPU (needs SSDT-PNLF).", option: \.applbkl3),
	]

	private var gpus: [RadeonGPU] = []
	private var gpu: RadeonGPU?
	private var options: RadeonOptions?

	private let output = PlistOutputView()
	private lazy var gpuPopUp = ControlBar.popUp([], target: self, action: #selector(gpuChanged(_:)))
	private let nameLabel = NSTextField(labelWithString: "")
	private let familyLabel = NSTextField(labelWithString: "")
	private let supportLabel = NSTextField(labelWithString: "")
	private let notesLabel = NSTextField(wrappingLabelWithString: "")
	private let deviceIDField = Form.textField(monospaced: true, placeholder: "0x73BF")
	private let pathField = Form.textField(monospaced: true)
	private let spoofField = Form.textField(monospaced: true, placeholder: "None")
	private let modelField = Form.textField(placeholder: "Automatic")
	private let slotField = Form.textField(placeholder: "Slot-1")
	private lazy var shikigvaPopUp = ControlBar.popUp([L("Off"), "16", "80"], target: self, action: #selector(optionChanged(_:)))
	private var checkboxes: [(NSButton, WritableKeyPath<RadeonOptions, Bool>)] = []

	override func loadView() {
		[deviceIDField, pathField, spoofField, modelField, slotField].forEach { $0.delegate = self }
		pathField.toolTip = L("The GPU's PCI device path. Cards with a PCIe switch (most Navi cards) sit a few Pci() levels deeper than the slot.")
		spoofField.toolTip = L("A supported device ID to present instead (device-id). Set a model name as well, since the automatic one will be wrong.")
		shikigvaPopUp.toolTip = L("80: AMD DRM for Music, Safari and TV. Fall back to 16 if it freezes.")
		notesLabel.textColor = .secondaryLabelColor

		let cardGrid = Form.grid([
			("Name", nameLabel), ("Family", familyLabel), ("macOS", supportLabel),
			("Device ID", deviceIDField), ("Device Path", pathField),
		])
		let card = Form.box("Card", content: stack([cardGrid, notesLabel]))

		let propertyFields = Form.grid([
			("Spoof Device ID", spoofField), ("Model", modelField), ("Slot Name", slotField), ("shikigva", shikigvaPopUp),
		])
		let properties = Form.box("Device Properties", content: stack(toggles(Self.propertyToggles) + [propertyFields]))
		let bootArgs = Form.box("Boot Arguments", content: stack(toggles(Self.bootArgToggles)))

		let warning = NSTextField(wrappingLabelWithString: L("Experimental: these settings come from WhateverGreen's documentation and haven't been tested on every card. Keep a working EFI to boot from."))
		warning.textColor = .systemOrange
		let form = Form.scrollingStack([warning, card, properties, bootArgs])

		let split = NSSplitView()
		split.isVertical = true
		split.dividerStyle = .thin
		split.addArrangedSubview(form)
		split.addArrangedSubview(output)
		form.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
		let formWidth = form.widthAnchor.constraint(equalToConstant: 520)
		formWidth.priority = .defaultLow
		formWidth.isActive = true

		let header = ControlBar.make([ControlBar.label("GPU"), gpuPopUp], trailing: [
			ControlBar.iconButton(.gitHub, toolTip: "NootedRed (Ryzen APU graphics)", target: self, action: #selector(openNootedRed(_:))),
		])
		let footer = ControlBar.make([output.modeControl], trailing: [
			ControlBar.button("Copy", symbol: .copy, target: self, action: #selector(copyOutput(_:))),
			ControlBar.button("Apply to config.plist…", symbol: .wand, target: self, action: #selector(apply(_:))),
		])
		view = ControlBar.stack(header: header, content: split, footer: footer)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		reloadGPUs()
	}

	private func stack(_ views: [NSView]) -> NSStackView {
		let stack = NSStackView(views: views)
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 8
		views.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
		return stack
	}

	private func toggles(_ toggles: [Toggle]) -> [NSView] {
		return toggles.map { toggle in
			let checkbox = Form.checkbox(toggle.title, target: self, action: #selector(optionChanged(_:)))
			checkbox.toolTip = L(toggle.detail)
			checkboxes.append((checkbox, toggle.option))
			return checkbox
		}
	}

	// MARK: GPUs

	private func reloadGPUs() {
		gpus = RadeonGPU.detected()
		gpuPopUp.removeAllItems()
		gpuPopUp.addItems(withTitles: gpus.map { $0.title })
		gpuPopUp.addItem(withTitle: L("Another card…"))
		gpuPopUp.selectItem(at: 0)
		select(gpus.first ?? manualGPU())
	}

	/// The card typed in for a machine other than this one.
	private func manualGPU() -> RadeonGPU {
		let deviceID = UInt32(deviceIDField.stringValue.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive), radix: 16) ?? 0x73BF
		if deviceIDField.stringValue.isEmpty {
			deviceIDField.stringValue = String(format: "0x%04X", deviceID)
		}
		let path = pathField.stringValue.isEmpty ? "PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)" : pathField.stringValue
		return RadeonGPU.manual(deviceID: deviceID, devicePath: path)
	}

	private func select(_ gpu: RadeonGPU) {
		self.gpu = gpu
		options = RadeonOptions(for: gpu)
		spoofField.stringValue = ""
		modelField.stringValue = ""
		slotField.stringValue = ""
		shikigvaPopUp.selectItem(at: 0)
		pathField.stringValue = gpu.devicePath
		deviceIDField.stringValue = String(format: "0x%04X", gpu.deviceID)
		deviceIDField.isEditable = !gpu.isDetected
		deviceIDField.isBordered = !gpu.isDetected
		deviceIDField.drawsBackground = !gpu.isDetected
		updateCard()
		updateControls()
		generate()
	}

	private func updateCard() {
		guard let gpu = gpu else { return }
		nameLabel.stringValue = gpu.name
		familyLabel.stringValue = gpu.family.name
		supportLabel.stringValue = gpu.family.support
		notesLabel.stringValue = gpu.notes.map { "• " + $0 }.joined(separator: "\n")
	}

	private func updateControls() {
		guard let options = options else { return }
		for (checkbox, option) in checkboxes {
			checkbox.state = options[keyPath: option] ? .on : .off
			// With disable-gpu set nothing else is written, so the other properties are greyed out.
			checkbox.isEnabled = option == \.disableGPU || !options.disableGPU || Self.bootArgToggles.contains { $0.option == option }
		}
		[spoofField, modelField, slotField].forEach { $0.isEnabled = !options.disableGPU }
		shikigvaPopUp.isEnabled = !options.disableGPU
	}

	private func generate() {
		guard let options = options else { return }
		output.string = RadeonConfig.preview(path: pathField.stringValue, options: options, format: BootloaderConfigFormat.current)
	}

	// MARK: SectionContent

	var canRefresh: Bool { return true }
	func refresh() { reloadGPUs() }

	// MARK: Actions

	@objc private func gpuChanged(_ sender: NSPopUpButton) {
		let index = sender.indexOfSelectedItem
		if gpus.indices.contains(index) {
			select(gpus[index])
		} else {
			deviceIDField.stringValue = ""
			pathField.stringValue = ""
			select(manualGPU())
		}
	}

	@objc private func optionChanged(_ sender: Any?) {
		guard var options = options else { return }
		for (checkbox, option) in checkboxes {
			options[keyPath: option] = checkbox.state == .on
		}
		let spoof = spoofField.stringValue.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
		options.spoofDeviceID = spoof.isEmpty ? nil : UInt32(spoof, radix: 16)
		options.model = modelField.stringValue
		options.slotName = slotField.stringValue
		options.shikigva = [0, 16, 80][max(0, shikigvaPopUp.indexOfSelectedItem)]
		self.options = options
		updateControls()
		generate()
	}

	func controlTextDidChange(_ notification: Notification) {
		guard let field = notification.object as? NSTextField else { return }
		if field === deviceIDField, gpu?.isDetected == false {
			let options = self.options
			gpu = manualGPU()
			self.options = options
			updateCard()
		} else if field === pathField {
			gpu?.devicePath = pathField.stringValue
		}
		optionChanged(nil)
	}

	@objc private func copyOutput(_ sender: Any?) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(output.string, forType: .string)
	}

	@objc private func openNootedRed(_ sender: Any?) {
		NSWorkspace.shared.open(URL(string: "https://github.com/ChefKissInc/NootedRed")!)
	}

	@objc private func apply(_ sender: Any?) {
		guard let options = options else { return }
		let path = pathField.stringValue.trimmingCharacters(in: .whitespaces)
		guard path.hasPrefix("PciRoot(") else {
			Alerts.show("Enter the GPU's device path first.", "For example PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0).")
			return
		}
		guard !options.properties().isEmpty || !options.bootArgs.isEmpty else {
			Alerts.show("Nothing to apply.", "Tick the properties or boot arguments you want first.")
			return
		}
		ConfigPlistPicker.choose { config, url in
			RadeonConfig.apply(path: path, options: options, to: config)
			do {
				try config.write(to: url)
				Alerts.show("Patch Success!", url.path)
			} catch {
				Alerts.error("Couldn't write the config.plist.", error.localizedDescription)
			}
		}
	}
}
