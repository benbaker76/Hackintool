//
//  ExtensionsViewController.swift
//  Hackintool
//
//  Extensions section: well-known Hackintosh kexts with loaded, source and release
//  versions; selected kexts can be downloaded or built from source.
//

import Cocoa

final class ExtensionsViewController: NSViewController, SectionContent {
	private var entries: [KextEntry] = []
	private var selectedNames = Set<String>()

	private lazy var table = DataTableViewController<KextEntry>(columns: [
		DataColumn("Select", "", width: 24) { [unowned self] in self.selectedNames.contains($0.name) ? "1" : "0" }
			.with(customView: { [unowned self] entry in self.checkbox(for: entry) }),
		DataColumn("Name", "Name", width: 170) { $0.name }
			.with(image: { $0.isLiluPlugin ? Symbol.puzzle.image() : Symbol.package.image() }),
		DataColumn("Status", "Status", width: 110) { ExtensionsViewController.status(of: $0).title }
			.with(customView: { entry in
				let status = ExtensionsViewController.status(of: entry)
				return StatusBadge.make(status.title, color: status.color, symbol: status.symbol)
			}),
		DataColumn("InstalledVersion", "Installed", width: 80) { $0.installedVersion ?? "" },
		DataColumn("CurrentVersion", "Current", width: 80) { $0.currentVersion ?? "" },
		DataColumn("DownloadVersion", "Download", width: 80) { $0.downloadVersion ?? "" },
		DataColumn("Superseder", "Replaced By", width: 110) { $0.superseder ?? "" },
		DataColumn("Description", "Description", width: 360) { $0.description },
	])
	private let output = ScrollingTextView(editable: false, monospaced: true, wraps: false)
	private let progressBar = NSProgressIndicator()
	private lazy var installedOnlyCheckbox = Form.checkbox("Show Installed Only", target: self, action: #selector(toggleInstalledOnly(_:)))
	private lazy var actionButtons = [
		ControlBar.button("Check Versions", symbol: .refresh, target: self, action: #selector(checkVersions(_:))),
		ControlBar.button("Download", symbol: .import, target: self, action: #selector(downloadSelected(_:))),
		ControlBar.button("Build", symbol: .terminal, target: self, action: #selector(buildSelected(_:))),
	]

	/// Installed, up to date or behind the latest release.
	static func status(of entry: KextEntry) -> (title: String, color: NSColor, symbol: Symbol?) {
		guard let installed = entry.installedVersion else {
			return entry.superseder != nil ? (L("Obsolete"), .secondaryLabelColor, nil) : ("", .clear, nil)
		}
		guard let latest = entry.downloadVersion ?? entry.currentVersion else {
			return (L("Installed"), .systemBlue, .checkCircle)
		}
		return VersionNumber.isNewer(latest, than: installed)
			? (L("Update"), .systemOrange, .updateCircle)
			: (L("Up to Date"), .systemGreen, .checkCircle)
	}

	override func loadView() {
		addChild(table)
		installedOnlyCheckbox.state = Settings.showInstalledOnly ? .on : .off
		table.contextMenuItems = [
			{
				let item = NSMenuItem(title: L("Open Url"), action: #selector(openProjectPage(_:)), keyEquivalent: "")
				item.target = self
				return item
			}(),
		]
		table.onDoubleClick = { entry in
			URL(string: entry.projectURL).map { _ = NSWorkspace.shared.open($0) }
		}

		progressBar.style = .bar
		progressBar.isIndeterminate = false
		progressBar.minValue = 0
		progressBar.maxValue = 1
		progressBar.controlSize = .small
		progressBar.widthAnchor.constraint(equalToConstant: 160).isActive = true
		progressBar.isHidden = true

		let header = ControlBar.make([installedOnlyCheckbox, progressBar], trailing: actionButtons)
		let split = NSSplitView()
		split.isVertical = false
		split.dividerStyle = .thin
		split.addArrangedSubview(table.view)
		split.addArrangedSubview(output.scrollView)
		let tableHeight = split.arrangedSubviews[0].heightAnchor.constraint(equalTo: split.heightAnchor, multiplier: 0.65)
		tableHeight.priority = .defaultLow
		tableHeight.isActive = true
		output.scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
		view = ControlBar.stack(header: header, content: split)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		refresh()
	}

	private var visibleEntries: [KextEntry] {
		return Settings.showInstalledOnly ? entries.filter { $0.installedVersion != nil } : entries
	}

	private func reload() {
		table.setRows(visibleEntries)
	}

	// MARK: SectionContent

	var canRefresh: Bool { return true }

	func refresh() {
		DispatchQueue.global(qos: .userInitiated).async {
			let entries = KextCatalog.load()
			DispatchQueue.main.async {
				self.entries = entries
				self.reload()
			}
		}
	}

	var searchPlaceholder: String? { return table.searchPlaceholder }
	func search(_ text: String) { table.search(text) }

	// MARK: Selection

	private func checkbox(for entry: KextEntry) -> NSView {
		let checkbox = KextCheckbox(entry: entry, target: self, action: #selector(toggleEntry(_:)))
		checkbox.state = selectedNames.contains(entry.name) ? .on : .off
		return checkbox
	}

	@objc private func toggleEntry(_ sender: KextCheckbox) {
		if sender.state == .on {
			selectedNames.insert(sender.entry.name)
		} else {
			selectedNames.remove(sender.entry.name)
		}
	}

	private var selectedEntries: [KextEntry] {
		return visibleEntries.filter { selectedNames.contains($0.name) }
	}

	@objc private func toggleInstalledOnly(_ sender: NSButton) {
		Settings.showInstalledOnly = sender.state == .on
		reload()
	}

	@objc private func openProjectPage(_ sender: Any?) {
		guard let entry = table.targetRows.first, let url = URL(string: entry.projectURL) else { return }
		NSWorkspace.shared.open(url)
	}

	// MARK: Jobs

	private func setBusy(_ busy: Bool) {
		actionButtons.forEach { $0.isEnabled = !busy }
		installedOnlyCheckbox.isEnabled = !busy
		progressBar.isHidden = !busy
		progressBar.doubleValue = 0
	}

	private lazy var jobs = KextJobs(output: { [weak self] text, isError in
		self?.output.append(text, color: isError ? .systemRed : .labelColor)
	}, progress: { [weak self] fraction in
		self?.progressBar.doubleValue = fraction
	})

	@objc private func checkVersions(_ sender: Any?) {
		let entries = visibleEntries
		setBusy(true)
		KextCatalog.checkVersions(entries, progress: { [weak self] index in
			guard let self = self else { return }
			self.progressBar.doubleValue = Double(index + 1) / Double(entries.count)
			self.table.reload()
		}, completion: { [weak self] in
			self?.setBusy(false)
			self?.table.reload()
		})
	}

	@objc private func downloadSelected(_ sender: Any?) {
		let entries = selectedEntries
		guard !entries.isEmpty else {
			Alerts.show("No kexts selected.", "Tick the kexts to download first.")
			return
		}
		output.clear()
		setBusy(true)
		jobs.download(entries) { [weak self] folder in
			self?.setBusy(false)
			NSWorkspace.shared.activateFileViewerSelecting([folder])
		}
	}

	@objc private func buildSelected(_ sender: Any?) {
		let entries = selectedEntries
		guard !entries.isEmpty else {
			Alerts.show("No kexts selected.", "Tick the kexts to build first.")
			return
		}
		guard KextJobs.hasDeveloperTools else {
			Alerts.error("Missing Xcode Tools!", "Open Terminal and run\nxcode-select --install")
			return
		}
		output.clear()
		setBusy(true)
		let lilu = self.entries.first { $0.isLilu }
		jobs.build(entries, lilu: lilu) { [weak self] folder in
			self?.setBusy(false)
			NSWorkspace.shared.activateFileViewerSelecting([folder])
		}
	}
}

final class KextCheckbox: NSButton {
	let entry: KextEntry

	init(entry: KextEntry, target: AnyObject, action: Selector) {
		self.entry = entry
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
