//
//  PowerViewController.swift
//  Hackintool
//
//  Power section: pmset settings currently in use, editable, with a one-click fix
//  for sleep problems caused by hibernation on Hackintosh systems.
//

import Cocoa

struct PowerSetting {
	let name: String
	let value: String

	/// Settings that should be 0 on a Hackintosh: hibernation and proximity wake break sleep.
	static let shouldBeZero: Set<String> = ["hibernatemode", "proximitywake"]

	var status: Bool? {
		guard PowerSetting.shouldBeZero.contains(name) else { return nil }
		return value == "0"
	}
}

enum PowerManagement {
	/// Parses `pmset -g`, returning the "Currently in use" section.
	static func currentSettings() -> [PowerSetting] {
		guard let output = Shell.output("/usr/bin/pmset", ["-g"]) else { return [] }
		var inCurrentSection = false
		var settings: [PowerSetting] = []
		for line in output.split(separator: "\n") {
			if line.hasPrefix("Currently in use:") {
				inCurrentSection = true
				continue
			}
			guard inCurrentSection else { continue }
			let fields = line.split(separator: " ", omittingEmptySubsequences: true)
			guard fields.count >= 2 else { continue }
			settings.append(PowerSetting(name: String(fields[0]), value: String(fields[1])))
		}
		return settings.sorted { $0.name < $1.name }
	}

	@discardableResult
	static func set(_ name: String, to value: String) -> Bool {
		return Privileges.shared.run("/usr/bin/pmset", ["-a", name, value]) != nil
	}

	/// Disables hibernation and proximity wake, and replaces the sleep image with a
	/// locked empty file so macOS can't recreate it.
	static func fixSleepImage(current: [PowerSetting]) {
		let value = { (name: String) in current.first { $0.name == name }?.value }
		set("hibernatemode", to: "0")
		if value("proximitywake") != nil {
			set("proximitywake", to: "0")
		}
		if let hibernateFile = value("hibernatefile") {
			Privileges.shared.run("/bin/rm", [hibernateFile])
			Privileges.shared.run("/usr/bin/touch", [hibernateFile])
			Privileges.shared.run("/usr/bin/chflags", ["uchg", hibernateFile])
		}
	}
}

final class PowerViewController: NSViewController, SectionContent {
	private lazy var table = DataTableViewController<PowerSetting>(columns: [
		DataColumn("Name", "Name", width: 220) { $0.name },
		DataColumn("Value", "Value", width: 300, onEdit: { [weak self] setting, value in
			self?.change(setting, to: value)
		}) { $0.value },
	])

	override func loadView() {
		addChild(table)
		table.rowColor = { setting in
			setting.status.map { $0 ? .systemGreen : .systemRed }
		}
		let footer = ControlBar.make([
			ControlBar.label("Green and red rows show settings that affect sleep on a Hackintosh."),
		], trailing: [
			ControlBar.button("Fix Sleep Image", symbol: .wand, target: self, action: #selector(fixSleepImage(_:))),
		])
		view = ControlBar.stack(header: nil, content: table.view, footer: footer)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		refresh()
	}

	var canRefresh: Bool { return true }

	func refresh() {
		DispatchQueue.global(qos: .userInitiated).async {
			let settings = PowerManagement.currentSettings()
			DispatchQueue.main.async { self.table.setRows(settings) }
		}
	}

	var searchPlaceholder: String? { return table.searchPlaceholder }
	func search(_ text: String) { table.search(text) }

	private func change(_ setting: PowerSetting, to value: String) {
		PowerManagement.set(setting.name, to: value)
		refresh()
	}

	@objc private func fixSleepImage(_ sender: Any?) {
		PowerManagement.fixSleepImage(current: table.rows)
		refresh()
	}
}
