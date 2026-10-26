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

#if DEBUG
/// HACKINTOOL_FBTEST=1: parse every bundled framebuffer table and print a summary, then quit.
enum FramebufferSelfTest {
	static func runIfRequested() {
		guard ProcessInfo.processInfo.environment["HACKINTOOL_FBTEST"] != nil else { return }
		for source in [FramebufferTable.Source.macOS10_13_6, .macOS10_14] {
			for generation in IntelGeneration.allCases {
				guard let table = FramebufferTable.load(generation, from: source) else {
					print("\(source) \(generation.name): not found")
					continue
				}
				let first = table.modified[table.modified.count > 1 ? 1 : 0]
				let connectors = first.connectors.map { "[\($0.index)] bus 0x\(String($0.busID, radix: 16)) pipe \($0.pipe) \($0.typeName) 0x\(String($0.flags, radix: 16))" }
				print("\(source) \(generation.name): \(table.original.count) records, ids \(table.platformIDs.prefix(4).map { String(format: "0x%08X", $0) }.joined(separator: " "))")
				print("   #1 mobile \(first.isMobile) pipes \(first.pipeCount) ports \(first.portCount) stolen \(first.stolenMemory.map { ByteFormatting.memory($0) } ?? "-") fb \(first.framebufferMemory.map { ByteFormatting.memory($0) } ?? "-") flags \(first.flags.map { String(format: "0x%08X", $0) } ?? "-") camellia \(first.camellia.map(String.init) ?? "-")")
				print("   " + connectors.joined(separator: " | "))
			}
		}
		if ProcessInfo.processInfo.environment["HACKINTOOL_FBTEST"] == "patch" {
			// Edit a Coffee Lake record and print each output format.
			guard let table = FramebufferTable.load(.coffeeLake, from: .macOS10_14), let index = table.index(of: 0x3E9B_0007) else { exit(1) }
			var connector = table.modified[index].connector(at: 1)
			connector.type = ConnectorType.hdmi.rawValue
			table.modified[index].setConnector(connector, at: 1)
			table.modified[index].stolenMemory = 0x0200_0000
			let context = PatchContext(table: table, index: index, pciDevices: [PatchContext.fakeIGPU], audioDevices: [], displays: [], injectedDeviceID: nil)
			print(FramebufferPatcher.kextsToPatch(context: context, format: .hex))
			print(FramebufferPatcher.kextsToPatch(context: context, format: .base64))
			print(FramebufferPatcher.ssdt(context: context, forceAll: true))
		}
		exit(0)
	}
}
#endif
