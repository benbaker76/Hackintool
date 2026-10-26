//
//  UtilitiesViewController.swift
//  Hackintool
//
//  Utilities section: a list of maintenance tools, each with a description and a
//  button, above a log of the commands they run.
//

import Cocoa

final class UtilitiesViewController: NSViewController {
	private let output = ScrollingTextView(editable: false, monospaced: true, wraps: true)
	private lazy var log = AdminCommandLog { [weak self] text, style in
		self?.append(text, style)
	}
	private var aiiCheckboxes: [NSButton] = []

	override func loadView() {
		var rows: [NSView] = [
			ToolRow.make(symbol: .extensions, title: "Install Kext(s)",
			             detail: "Copy kexts into /Library/Extensions and rebuild the kext cache.",
			             button: "Install…", target: self, action: #selector(installKexts(_:))),
			ToolRow.make(symbol: .refresh, title: "Rebuild KextCache and Repair Permissions",
			             detail: "Fix kext ownership and permissions and rebuild the kernel extension cache.",
			             button: "Rebuild", target: self, action: #selector(rebuildKextCache(_:))),
			ToolRow.make(symbol: .unlock, title: "Disable Gatekeeper",
			             detail: Utilities.isBigSurOrLater ? "Allow apps from anywhere (spctl --master-disable)." : "Allow apps from anywhere and mount the system volume read/write.",
			             button: "Disable", target: self, action: #selector(disableGatekeeper(_:))),
			ToolRow.make(symbol: .export, title: "Dump ACPI",
			             detail: "Save the DSDT and SSDTs from this boot and disassemble them with iasl.",
			             button: "Dump…", target: self, action: #selector(dumpACPI(_:))),
			ToolRow.make(symbol: .disks, title: "Install SATA Hotplug Fix",
			             detail: "AppleAHCIPortHotplug.kext makes internal SATA ports show as internal.",
			             button: "Install…", target: self, action: #selector(installSATAHotplugFix(_:))),
		]
		if !Utilities.isBigSurOrLater {
			rows.append(ToolRow.make(symbol: .network, title: "Install Atheros Kext",
			                         detail: "Support for Atheros AR9xxx Wi-Fi (macOS 10.15 and earlier).",
			                         button: "Install", target: self, action: #selector(installAtheros(_:))))
		}
		rows += [
			ToolRow.make(symbol: .bluetooth, title: "Windows Bluetooth Registry File",
			             detail: "Export pairing keys so Bluetooth devices work in Windows without re-pairing.",
			             button: "Create…", target: self, action: #selector(createBluetoothRegistryFile(_:))),
			ToolRow.make(symbol: .settings, title: "Windows UTC Registry Files",
			             detail: "Make Windows keep the hardware clock in UTC, like macOS.",
			             button: "Create…", target: self, action: #selector(createUTCRegistryFiles(_:))),
		]
		// AppleIntelInfo.kext is x86_64 only.
		if !SystemInfo.isAppleSilicon {
			rows.append(appleIntelInfoRow())
		}

		let list = Form.scrollingStack(rows, spacing: 0, insets: NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
		let split = NSSplitView()
		split.isVertical = false
		split.dividerStyle = .thin
		split.addArrangedSubview(list)
		split.addArrangedSubview(output.scrollView)
		let listHeight = list.heightAnchor.constraint(equalTo: split.heightAnchor, multiplier: 0.62)
		listHeight.priority = .defaultLow
		listHeight.isActive = true
		output.scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
		view = split
	}

	private func appleIntelInfoRow() -> NSView {
		let options = Utilities.AppleIntelInfoOptions()
		let checkboxes: [(String, String, Bool)] = [
			("Enable HWP", "AII_EnableHWP", options.enableHWP),
			("Log CStates", "AII_LogCStates", options.logCStates),
			("Log IGPU", "AII_LogIGPU", options.logIGPU),
			("Log IPG Style", "AII_LogIPGStyle", options.logIPGStyle),
			("Log Intel Regs", "AII_LogIntelRegs", options.logIntelRegs),
			("Log MSRs", "AII_LogMSRs", options.logMSRs),
		]
		aiiCheckboxes = checkboxes.map { title, identifier, isOn in
			let checkbox = Form.checkbox(title, identifier: identifier, target: self, action: #selector(aiiOptionChanged(_:)))
			checkbox.state = isOn ? .on : .off
			checkbox.controlSize = .small
			checkbox.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
			return checkbox
		}
		let optionsRow = NSStackView(views: aiiCheckboxes)
		optionsRow.spacing = 12
		return ToolRow.make(symbol: .framebuffer, title: "AppleIntelInfo",
		                    detail: "Load AppleIntelInfo.kext to report CPU power states, P-states and registers.",
		                    accessory: optionsRow, button: "Run", target: self, action: #selector(runAppleIntelInfo(_:)))
	}

	private func append(_ text: String, _ style: AdminCommandLog.Style) {
		switch style {
		case .heading: output.append(text, color: .systemOrange)
		case .command: output.append(text, color: .secondaryLabelColor)
		case .output: output.append(text)
		case .error: output.append(text, color: .systemRed)
		}
	}

	/// Runs a task off the main thread after making sure we have admin rights.
	private func runAdminTask(_ work: @escaping () -> Void) {
		guard Privileges.shared.unlock() else { return }
		output.clear()
		DispatchQueue.global(qos: .userInitiated).async(execute: work)
	}

	// MARK: Actions

	@objc private func installKexts(_ sender: Any?) {
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = true
		panel.canChooseDirectories = false
		FilePanels.setAllowedExtensions(["kext"], on: panel)
		panel.prompt = L("Select")
		guard let window = view.window else { return }
		panel.beginSheetModal(for: window) { response in
			guard response == .OK, !panel.urls.isEmpty else { return }
			let kexts = panel.urls
			self.runAdminTask { Utilities.install(kexts, to: Utilities.extensionsPath, log: self.log) }
		}
	}

	@objc private func rebuildKextCache(_ sender: Any?) {
		runAdminTask { Utilities.rebuildKextCache(log: self.log) }
	}

	@objc private func disableGatekeeper(_ sender: Any?) {
		Alerts.confirm("Disable Gatekeeper and mount the disk in read/write mode?", "This is required for some operations on macOS 10.15+", confirmTitle: "Disable") { confirmed in
			guard confirmed else { return }
			self.runAdminTask { Utilities.disableGatekeeperAndMountRootWritable(log: self.log) }
		}
	}

	@objc private func dumpACPI(_ sender: Any?) {
		FilePanels.chooseFolder(prompt: "Choose a destination folder") { folder in
			self.output.clear()
			DispatchQueue.global(qos: .userInitiated).async {
				Utilities.dumpACPITables(to: folder) { text, isError in
					self.output.append(text, color: isError ? .systemRed : .labelColor)
				}
				DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
			}
		}
	}

	/// Asks where to put AppleAHCIPortHotplug.kext: /Library/Extensions (installed and the kext
	/// cache rebuilt) or the bootloader's kexts folder, e.g. EFI/OC/Kexts.
	@objc private func installSATAHotplugFix(_ sender: Any?) {
		guard let kext = Utilities.bundledKext("AppleAHCIPortHotplug"), let window = view.window else { return }
		let panel = NSOpenPanel()
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.canCreateDirectories = true
		panel.directoryURL = URL(fileURLWithPath: Utilities.extensionsPath)
		panel.message = L("Choose /Library/Extensions, or your bootloader's kexts folder (e.g. EFI/OC/Kexts).")
		panel.prompt = L("Install")
		panel.beginSheetModal(for: window) { response in
			guard response == .OK, let folder = panel.url else { return }
			if folder.standardizedFileURL.path == URL(fileURLWithPath: Utilities.extensionsPath).standardizedFileURL.path {
				self.runAdminTask { Utilities.install([kext], to: Utilities.extensionsPath, log: self.log) }
			} else {
				self.runAdminTask { Utilities.copy([kext], to: folder.path, log: self.log) }
			}
		}
	}

	@objc private func installAtheros(_ sender: Any?) {
		runAdminTask { Utilities.installAtherosKext(log: self.log) }
	}

	@objc private func createBluetoothRegistryFile(_ sender: Any?) {
		FilePanels.save(suggestedName: "Bluetooth.reg", allowedExtensions: ["reg"]) { url in
			DispatchQueue.global(qos: .userInitiated).async {
				let export = WindowsBluetooth.export()
				DispatchQueue.main.async {
					guard export.deviceCount > 0 else {
						Alerts.error("No Bluetooth pairing keys found.",
						             "Pair your devices in macOS first. If you cancelled the password prompt, try again and allow access to the System keychain.")
						return
					}
					FilePanels.write([(url.lastPathComponent, export.registryFile)], to: url.deletingLastPathComponent())
					self.output.append(L("Exported %d Bluetooth device(s).", export.deviceCount) + "\n", color: .systemGreen)
				}
			}
		}
	}

	@objc private func createUTCRegistryFiles(_ sender: Any?) {
		FilePanels.chooseFolder(prompt: "Save") { folder in
			let files = Utilities.createWindowsUTCRegistryFiles(in: folder)
			NSWorkspace.shared.activateFileViewerSelecting(files)
		}
	}

	@objc private func aiiOptionChanged(_ sender: NSButton) {
		let isOn = sender.state == .on
		switch sender.identifier?.rawValue {
		case "AII_EnableHWP":
			if isOn {
				warn(sender, "Enabling HWP (Intel Speed Shift) will require a reboot to restore the previous value.") { Settings.aiiEnableHWP = $0 }
			} else {
				Settings.aiiEnableHWP = false
			}
		case "AII_LogIntelRegs":
			if isOn {
				warn(sender, "Logging Intel registers may cause your system to crash.") { Settings.aiiLogIntelRegs = $0 }
			} else {
				Settings.aiiLogIntelRegs = false
			}
		case "AII_LogCStates": Settings.aiiLogCStates = isOn
		case "AII_LogIGPU": Settings.aiiLogIGPU = isOn
		case "AII_LogIPGStyle": Settings.aiiLogIPGStyle = isOn
		case "AII_LogMSRs": Settings.aiiLogMSRs = isOn
		default: break
		}
	}

	/// Confirms a risky option, unticking it if the user cancels.
	private func warn(_ checkbox: NSButton, _ message: String, apply: @escaping (Bool) -> Void) {
		Alerts.confirm("Warning!", message, confirmTitle: "OK") { confirmed in
			checkbox.state = confirmed ? .on : .off
			apply(confirmed)
		}
	}

	@objc private func runAppleIntelInfo(_ sender: NSButton) {
		let options = Utilities.AppleIntelInfoOptions()
		sender.isEnabled = false
		runAdminTask {
			let report = Utilities.runAppleIntelInfo(options, log: self.log) { seconds in
				DispatchQueue.main.async {
					self.append(L("Logging CStates") + " — " + L("Perform CPU intensive activity...") + "\n", .heading)
				}
				Thread.sleep(forTimeInterval: seconds)
			}
			DispatchQueue.main.async {
				sender.isEnabled = true
				if let report = report {
					self.output.string = report
				}
			}
		}
	}
}

/// One tool: icon, title, description, optional accessory controls and a button.
enum ToolRow {
	static func make(symbol: Symbol, title: String, detail: String, accessory: NSView? = nil,
	                 button buttonTitle: String, target: AnyObject, action: Selector) -> NSView {
		let icon = NSImageView(image: symbol.image(description: L(title), size: 22))
		icon.setSymbolSize(22)
		icon.setTint(.controlAccentColorCompat)

		let titleLabel = NSTextField(labelWithString: L(title))
		titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
		let detailLabel = NSTextField(wrappingLabelWithString: L(detail))
		detailLabel.textColor = .secondaryLabelColor
		detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

		var textViews: [NSView] = [titleLabel, detailLabel]
		if let accessory = accessory {
			textViews.append(accessory)
		}
		let text = NSStackView(views: textViews)
		text.orientation = .vertical
		text.alignment = .leading
		text.spacing = 3
		text.setContentHuggingPriority(.defaultLow, for: .horizontal)

		let button = NSButton(title: L(buttonTitle), target: target, action: action)
		button.bezelStyle = .rounded
		button.setContentHuggingPriority(.required, for: .horizontal)

		let row = NSStackView()
		row.setViews([icon, text], in: .leading)
		row.setViews([button], in: .trailing)
		row.orientation = .horizontal
		row.alignment = .centerY
		row.spacing = 12
		row.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)

		let separator = NSBox()
		separator.boxType = .separator
		let container = NSStackView(views: [row, separator])
		container.orientation = .vertical
		container.spacing = 0
		[row, separator].forEach { $0.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true }
		return container
	}
}
