//
//  LogsViewController.swift
//  Hackintool
//
//  Logs section: the bootloader's boot log, the latest Lilu log and a
//  filtered view of the unified system log.
//

import Cocoa

final class LogsViewController: TabbedViewController {
	init() {
		super.init(identifier: "Logs", pages: [
			Page(title: L("Boot"), viewController: BootLogViewController()),
			Page(title: L("Lilu"), viewController: LiluLogViewController()),
			Page(title: L("System"), viewController: SystemLogViewController()),
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}
}

/// A read-only log view; subclasses load the text.
class LogTextViewController: NSViewController, SectionContent {
	let output = ScrollingTextView(editable: false, monospaced: true, wraps: false)

	override func loadView() {
		view = output.scrollView
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		refresh()
	}

	var canRefresh: Bool { return true }
	func refresh() {}

	/// Find in the log uses the text view's find bar.
	var searchPlaceholder: String? { return L("Find in Log") }

	func search(_ text: String) {
		guard !text.isEmpty else { return }
		let range = (output.string as NSString).range(of: text, options: .caseInsensitive)
		guard range.location != NSNotFound else {
			NSSound.beep()
			return
		}
		output.textView.scrollRangeToVisible(range)
		output.textView.showFindIndicator(for: range)
		output.textView.setSelectedRange(range)
	}

	/// Loads text off the main thread.
	func load(_ work: @escaping () -> String?) {
		output.string = L("Loading…")
		DispatchQueue.global(qos: .userInitiated).async {
			let text = work()
			DispatchQueue.main.async { self.output.string = text ?? "" }
		}
	}
}

/// Logs ▸ Boot: the log OpenCore/Clover publishes, or dmesg if there isn't one.
final class BootLogViewController: LogTextViewController {
	override func viewDidLoad() {
		// Don't ask for a password just because the page was opened.
		output.string = BootLog.bootloaderLog() ?? L("No bootloader log found. Press Refresh to read the kernel log (dmesg), which needs administrator rights.")
	}

	override func refresh() {
		if let bootLog = BootLog.bootloaderLog() {
			output.string = bootLog
		} else {
			output.string = Privileges.shared.run("/sbin/dmesg")?.output ?? ""
		}
	}
}

/// Logs ▸ Lilu: the most recent /var/log/Lilu_* file (written with -liludump).
final class LiluLogViewController: LogTextViewController {
	override func refresh() {
		load {
			guard let url = BootLog.latestLiluLog() else { return L("No Lilu log found. Boot with -liludump to create one.") }
			return try? String(contentsOf: url, encoding: .utf8)
		}
	}
}

/// Logs ▸ System: `log show` for a process, optionally filtered by message text.
final class SystemLogViewController: LogTextViewController {
	private let processField = NSComboBox()
	private let containsField = NSComboBox()
	private lazy var lastBootCheckbox = Form.checkbox("Last Boot", target: nil, action: #selector(NSControl.performClick(_:)))

	override func loadView() {
		processField.addItems(withObjectValues: ["kernel", "Hackintool"])
		processField.stringValue = "kernel"
		containsField.addItems(withObjectValues: ["Lilu", "WhateverGreen", "AppleALC"])
		containsField.placeholderString = L("Any")
		lastBootCheckbox.state = .on
		lastBootCheckbox.target = nil
		lastBootCheckbox.action = nil
		[processField, containsField].forEach { $0.widthAnchor.constraint(equalToConstant: 160).isActive = true }

		let header = ControlBar.make([
			ControlBar.label("Process"), processField,
			ControlBar.label("Contains"), containsField,
			lastBootCheckbox,
			ControlBar.button("Show", symbol: .search, target: self, action: #selector(show(_:))),
		], trailing: [
			ControlBar.button("Erase Log", symbol: .trash, target: self, action: #selector(erase(_:))),
		])
		view = ControlBar.stack(header: header, content: output.scrollView)
	}

	override func viewDidLoad() {
		// Querying the log is slow; wait for the user to press Show.
	}

	override func refresh() {
		show(nil)
	}

	@objc private func show(_ sender: Any?) {
		var predicate = "process == \"\(processField.stringValue)\""
		let contains = containsField.stringValue.trimmingCharacters(in: .whitespaces)
		if !contains.isEmpty {
			predicate += " AND (eventMessage CONTAINS[c] \"\(contains)\")"
		}
		var arguments = ["show", "--style", "syslog", "--source"]
		if lastBootCheckbox.state == .on {
			arguments += ["--last", "boot"]
		}
		arguments += ["--predicate", predicate]
		load { Shell.output("/usr/bin/log", arguments) }
	}

	@objc private func erase(_ sender: Any?) {
		Alerts.confirm("Erase the system log?", "This deletes all log messages on this Mac.", confirmTitle: "Erase") { confirmed in
			guard confirmed else { return }
			self.output.string = Privileges.shared.run("/usr/bin/log", ["erase", "--all"])?.output ?? ""
		}
	}
}

enum BootLog {
	/// The boot log published by OpenCore (IOService:/boot-log) or Clover (efi/platform).
	static func bootloaderLog() -> String? {
		let data = IORegistryEntry(path: "IOService:/")?.data("boot-log") ?? IORegistryEntry(path: "IODeviceTree:/efi/platform")?.data("boot-log")
		return data.flatMap { String(data: $0, encoding: .ascii) }
	}

	static func latestLiluLog() -> URL? {
		let directory = URL(fileURLWithPath: "/var/log")
		let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
		return files
			.filter { $0.lastPathComponent.hasPrefix("Lilu_") }
			.max { modified($0) < modified($1) }
	}

	private static func modified(_ url: URL) -> Date {
		return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
	}
}
