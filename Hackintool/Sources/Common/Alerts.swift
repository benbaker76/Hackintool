//
//  Alerts.swift
//  Hackintool
//
//  Alerts and file panels, shown as sheets on the main window when there is one.
//

import Cocoa
import UniformTypeIdentifiers

enum Alerts {
	/// Shows an informational alert.
	static func show(_ message: String, _ information: String = "", style: NSAlert.Style = .informational) {
		let alert = NSAlert()
		alert.messageText = L(message)
		alert.informativeText = L(information)
		alert.alertStyle = style
		present(alert) { _ in }
	}

	static func error(_ message: String, _ information: String = "") {
		show(message, information, style: .warning)
	}

	/// Asks a yes/no question; `completion` receives true for the default (first) button.
	static func confirm(_ message: String, _ information: String = "", confirmTitle: String = "OK", completion: @escaping (Bool) -> Void) {
		let alert = NSAlert()
		alert.messageText = L(message)
		alert.informativeText = L(information)
		alert.addButton(withTitle: L(confirmTitle))
		alert.addButton(withTitle: L("Cancel"))
		present(alert) { completion($0 == .alertFirstButtonReturn) }
	}

	private static func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
		if let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
			alert.beginSheetModal(for: window, completionHandler: completion)
		} else {
			completion(alert.runModal())
		}
	}
}

enum FilePanels {
	/// Asks for a folder, starting on the Desktop.
	static func chooseFolder(prompt: String, completion: @escaping (URL) -> Void) {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.canCreateDirectories = true
		panel.prompt = L(prompt)
		panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
		begin(panel) { if let url = panel.url { completion(url) } }
	}

	/// Asks where to save a file.
	static func save(suggestedName: String, allowedExtensions: [String], directory: URL? = nil, completion: @escaping (URL) -> Void) {
		let panel = NSSavePanel()
		panel.nameFieldStringValue = suggestedName
		setAllowedExtensions(allowedExtensions, on: panel)
		panel.canCreateDirectories = true
		panel.directoryURL = directory ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
		begin(panel) { if let url = panel.url { completion(url) } }
	}

	/// Asks for a file to open.
	static func open(allowedExtensions: [String]?, directory: URL? = nil, completion: @escaping (URL) -> Void) {
		let panel = NSOpenPanel()
		panel.canChooseFiles = true
		panel.canChooseDirectories = false
		setAllowedExtensions(allowedExtensions, on: panel)
		panel.directoryURL = directory
		begin(panel) { if let url = panel.url { completion(url) } }
	}

	static func setAllowedExtensions(_ extensions: [String]?, on panel: NSSavePanel) {
		guard let extensions = extensions else { return }
		if #available(macOS 11.0, *) {
			panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
		} else {
			panel.allowedFileTypes = extensions
		}
	}

	private static func begin(_ panel: NSSavePanel, completion: @escaping () -> Void) {
		if let window = NSApp.mainWindow {
			panel.beginSheetModal(for: window) { if $0 == .OK { completion() } }
		} else if panel.runModal() == .OK {
			completion()
		}
	}

	/// Writes several text files into a folder and reveals them in Finder.
	static func write(_ files: [(name: String, contents: String)], to folder: URL) {
		var written: [URL] = []
		for file in files {
			let url = folder.appendingPathComponent(file.name)
			do {
				try file.contents.write(to: url, atomically: true, encoding: .utf8)
				written.append(url)
			} catch {
				Alerts.error("Export Failed", error.localizedDescription)
				return
			}
		}
		NSWorkspace.shared.activateFileViewerSelecting(written)
	}
}
