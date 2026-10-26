//
//  BootloaderViewController.swift
//  Hackintool
//
//  Bootloader section: which bootloader is running, its version against the latest
//  release (with a download), and optional ACPI/kext patches to merge into config.plist.
//

import Cocoa

/// A patch from the bundled Clover patch lists, offered for config.plist.
struct BootloaderPatch {
	enum Kind: String {
		case dsdtRename = "DSDT Rename"
		case kernel = "KernelToPatch"
		case kext = "KextsToPatch"
	}

	/// Position in the bundled list; comments aren't unique.
	let id: Int
	let kind: Kind
	let comment: String
	/// The patch in Clover format.
	let dictionary: [String: Any]

	/// Patches from Resources/Clover and Resources/USB that apply to the running macOS.
	static func bundled() -> [BootloaderPatch] {
		var patches: [BootloaderPatch] = []
		func load(_ name: String, _ directory: String) -> [String: Any] {
			return BundledData.plist(name, in: directory) as? [String: Any] ?? [:]
		}
		for (name, directory) in [("config_patches", "Clover"), ("config_patches", "USB")] {
			let section = load(name, directory)["KernelAndKextPatches"] as? [String: Any] ?? [:]
			for (key, kind) in [("KernelToPatch", Kind.kernel), ("KextsToPatch", Kind.kext)] {
				for patch in section[key] as? [[String: Any]] ?? [] where ConfigPlist.matchesCurrentOS(patch["MatchOS"] as? String) {
					patches.append(BootloaderPatch(id: patches.count, kind: kind, comment: patch["Comment"] as? String ?? "", dictionary: patch))
				}
			}
		}
		let renames = ((load("config_renames", "Clover")["ACPI"] as? [String: Any])?["DSDT"] as? [String: Any])?["Patches"] as? [[String: Any]] ?? []
		for patch in renames {
			patches.append(BootloaderPatch(id: patches.count, kind: .dsdtRename, comment: patch["Comment"] as? String ?? "", dictionary: patch))
		}
		return patches
	}

	func apply(to config: ConfigPlist) {
		switch kind {
		case .dsdtRename:
			guard let find = dictionary["Find"] as? Data, let replace = dictionary["Replace"] as? Data else { return }
			config.addACPIPatch(find: find, replace: replace, comment: comment)
		case .kernel:
			config.addKernelPatch(fromClover: dictionary, kernel: true)
		case .kext:
			config.addKernelPatch(fromClover: dictionary)
		}
	}
}

/// Release information for Clover and OpenCore on GitHub.
enum BootloaderRelease {
	case clover, openCore

	var name: String { return self == .clover ? "Clover" : "OpenCore" }
	var repository: (owner: String, repository: String) {
		return self == .clover ? ("CloverHackyColor", "CloverBootloader") : ("acidanthera", "OpenCorePkg")
	}
	var assetPrefix: String { return self == .clover ? "Clover_" : "OpenCore-" }
	var assetSuffix: String { return self == .clover ? ".pkg" : "RELEASE.zip" }

	static var current: BootloaderRelease {
		return BootloaderConfigFormat.current == .clover ? .clover : .openCore
	}
}

/// Bootloader section: the bootloader and its patches, and the AMD Vanilla patches.
final class BootloaderSectionViewController: TabbedViewController {
	init() {
		super.init(identifier: "Bootloader", pages: [
			Page(title: L("Bootloader"), viewController: BootloaderViewController()),
			Page(title: L("AMD Vanilla"), viewController: AMDVanillaViewController()),
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}
}

final class BootloaderViewController: NSViewController, SectionContent {
	private let info = PropertyListViewController(showsGroupHeaders: false)
	private var selectedPatches = Set<Int>()
	private lazy var patchTable = DataTableViewController<BootloaderPatch>(columns: [
		DataColumn("Select", "", width: 24) { [unowned self] in self.selectedPatches.contains($0.id) ? "1" : "0" }
			.with(customView: { [unowned self] patch in self.checkbox(for: patch) }),
		DataColumn("Type", "Type", width: 110) { L($0.kind.rawValue) },
		DataColumn("Comment", "Comment", width: 500) { $0.comment },
	])
	private lazy var bootloaderPopUp = ControlBar.popUp([L("Auto Detect"), "Clover", "OpenCore"], target: self, action: #selector(bootloaderChanged(_:)))
	private lazy var downloadButton = ControlBar.button("Download", symbol: .import, target: self, action: #selector(download(_:)))

	private var latestRelease: GitHub.Release?

	override func loadView() {
		addChild(info)
		addChild(patchTable)
		bootloaderPopUp.selectItem(at: Settings.selectedBootloader.rawValue)
		downloadButton.isEnabled = false

		let infoHeader = ControlBar.make([ControlBar.label("Bootloader"), bootloaderPopUp], trailing: [
			ControlBar.button("Check for Updates", symbol: .refresh, target: self, action: #selector(checkForUpdates(_:))),
			downloadButton,
		])
		let patchFooter = ControlBar.make([
			ControlBar.label("Selected patches are merged into the config.plist you choose; a backup is made first."),
		], trailing: [
			ControlBar.button("Apply Patches", symbol: .wand, target: self, action: #selector(applyPatches(_:))),
		])

		let split = NSSplitView()
		split.isVertical = false
		split.dividerStyle = .thin
		split.addArrangedSubview(ControlBar.stack(header: infoHeader, content: info.view))
		split.addArrangedSubview(ControlBar.stack(header: ControlBar.make([ControlBar.heading("Patches")]), content: patchTable.view, footer: patchFooter))
		let infoHeight = split.arrangedSubviews[0].heightAnchor.constraint(equalToConstant: 220)
		infoHeight.priority = .defaultLow
		infoHeight.isActive = true
		view = split
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		patchTable.setRows(BootloaderPatch.bundled())
		updateInfo()
		checkForUpdates(nil)
	}

	private func updateInfo() {
		let release = BootloaderRelease.current
		var items = [PropertyItem("Name", release.name)]
		switch Bootloader.detected {
		case .openCore(let version)? where release == .openCore:
			items.append(PropertyItem("Current Booted Version", version))
		case .clover(let booted, let installed)? where release == .clover:
			items.append(PropertyItem("Current Booted Version", booted))
			items.append(PropertyItem("Last Installed Version", installed))
		default:
			items.append(PropertyItem("Current Booted Version", L("Not detected")))
		}
		items.append(PropertyItem("Latest Available Version", latestRelease?.version ?? L("Checking…")))
		info.setItems(items)
		downloadButton.isEnabled = latestRelease?.asset(prefix: release.assetPrefix, suffix: release.assetSuffix) != nil
	}

	// MARK: SectionContent

	var canRefresh: Bool { return true }
	func refresh() { checkForUpdates(nil) }
	var searchPlaceholder: String? { return patchTable.searchPlaceholder }
	func search(_ text: String) { patchTable.search(text) }

	// MARK: Actions

	@objc private func bootloaderChanged(_ sender: NSPopUpButton) {
		Settings.selectedBootloader = BootloaderChoice(rawValue: sender.indexOfSelectedItem) ?? .autoDetect
		latestRelease = nil
		checkForUpdates(nil)
	}

	@objc private func checkForUpdates(_ sender: Any?) {
		let release = BootloaderRelease.current
		latestRelease = nil
		updateInfo()
		GitHub.latestRelease(owner: release.repository.owner, repository: release.repository.repository) { [weak self] latest in
			guard let self = self, BootloaderRelease.current == release else { return }
			self.latestRelease = latest
			self.updateInfo()
			if latest == nil, sender != nil {
				Alerts.error("Couldn't check for updates.", "GitHub could not be reached.")
			}
		}
	}

	@objc private func download(_ sender: Any?) {
		let release = BootloaderRelease.current
		guard let asset = latestRelease?.asset(prefix: release.assetPrefix, suffix: release.assetSuffix) else { return }
		FilePanels.save(suggestedName: asset.name, allowedExtensions: [(asset.name as NSString).pathExtension]) { [weak self] destination in
			guard let window = self?.view.window else { return }
			DownloadSheet.download(asset.downloadURL, to: destination, title: L("Downloading %@", asset.name), on: window) { file in
				if let file = file {
					NSWorkspace.shared.activateFileViewerSelecting([file])
				}
			}
		}
	}

	private func checkbox(for patch: BootloaderPatch) -> NSView {
		let checkbox = PatchCheckbox(patch: patch, target: self, action: #selector(togglePatch(_:)))
		checkbox.state = selectedPatches.contains(patch.id) ? .on : .off
		return checkbox
	}

	@objc private func togglePatch(_ sender: PatchCheckbox) {
		if sender.state == .on {
			selectedPatches.insert(sender.patch.id)
		} else {
			selectedPatches.remove(sender.patch.id)
		}
	}

	@objc private func applyPatches(_ sender: Any?) {
		let patches = patchTable.rows.filter { selectedPatches.contains($0.id) }
		guard !patches.isEmpty else {
			Alerts.show("No patches selected.", "Tick the patches you want to add first.")
			return
		}
		let name = BootloaderRelease.current.name
		Alerts.confirm(L("%@ Patch", name), L("Are you sure you want to apply %d %@ patch(s)?", patches.count, name), confirmTitle: "Apply") { confirmed in
			guard confirmed else { return }
			ConfigPlistPicker.choose { config, url in
				patches.forEach { $0.apply(to: config) }
				do {
					try config.write(to: url)
					self.selectedPatches.removeAll()
					self.patchTable.reload()
				} catch {
					Alerts.error("Couldn't write the config.plist.", error.localizedDescription)
				}
			}
		}
	}
}

/// A checkbox that remembers which patch it toggles.
final class PatchCheckbox: NSButton {
	let patch: BootloaderPatch

	init(patch: BootloaderPatch, target: AnyObject, action: Selector) {
		self.patch = patch
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
