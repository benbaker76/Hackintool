//
//  DebugSnapshot.swift
//  Hackintool
//
//  Debug builds only: renders the main window to PNG files and quits, for checking
//  layouts without screen-recording permission.
//
//    HACKINTOOL_SNAPSHOT=/tmp/shots HACKINTOOL_SNAPSHOT_SECTIONS=system,usb Hackintool.app/Contents/MacOS/Hackintool
//
//  Renders in light mode unless HACKINTOOL_SNAPSHOT_APPEARANCE=dark.
//

#if DEBUG
import Cocoa

enum DebugSnapshot {
	static func runIfRequested(_ windowController: MainWindowController) {
		let environment = ProcessInfo.processInfo.environment
		guard let directory = environment["HACKINTOOL_SNAPSHOT"] else { return }

		let sections = environment["HACKINTOOL_SNAPSHOT_SECTIONS"]?
			.split(separator: ",").compactMap { Section(rawValue: String($0)) } ?? Section.allCases
		// Light by default: cacheDisplay draws onto white, so dark-mode text would vanish.
		NSApp.appearance = NSAppearance(named: environment["HACKINTOOL_SNAPSHOT_APPEARANCE"] == "dark" ? .darkAqua : .aqua)
		try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

		var remaining = sections
		func next() {
			guard let section = remaining.first else {
				NSApp.terminate(nil)
				return
			}
			remaining.removeFirst()
			windowController.show(section)
			// Give the section time to load its data and lay out.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
				save(windowController.window, to: "\(directory)/\(section.rawValue).png")
				next()
			}
		}
		next()
	}

	private static func save(_ window: NSWindow?, to path: String) {
		guard let view = window?.contentView?.superview ?? window?.contentView,
		      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
		view.cacheDisplay(in: view.bounds, to: bitmap)
		try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))

		// Translucent materials (the sidebar) don't render through cacheDisplay, so also
		// save each table and outline view on its own.
		for (index, table) in tableViews(in: view).enumerated() {
			guard let tableBitmap = table.bitmapImageRepForCachingDisplay(in: table.visibleRect) else { continue }
			table.cacheDisplay(in: table.visibleRect, to: tableBitmap)
			let tablePath = (path as NSString).deletingPathExtension + "-table\(index).png"
			try? tableBitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: tablePath))
		}
	}

	private static func tableViews(in view: NSView) -> [NSTableView] {
		if let table = view as? NSTableView {
			return [table]
		}
		return view.subviews.flatMap(tableViews(in:))
	}
}
#endif
