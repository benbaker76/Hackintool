//
//  DebugSnapshot.swift
//  Hackintool
//
//  Debug builds only: renders the main window to PNG files and quits, for checking
//  layouts without screen-recording permission.
//
//    HACKINTOOL_SNAPSHOT=/tmp/shots HACKINTOOL_SNAPSHOT_SECTIONS=system,usb Hackintool.app/Contents/MacOS/Hackintool
//
//  Renders in light mode unless HACKINTOOL_SNAPSHOT_APPEARANCE=dark, at 2x (also used for
//  the README screenshots).
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
		guard let view = window?.contentView?.superview ?? window?.contentView else { return }
		view.layoutSubtreeIfNeeded()
		guard let windowBitmap = render(view, rect: view.bounds) else { return }

		// Behind-window materials (the sidebar) come out transparent, so composite: a solid
		// sidebar background, a selection highlight, the sidebar drawn on its own, then the window.
		let sidebar = tableViews(in: view).compactMap { $0 as? NSOutlineView }.first { $0.delegate is SidebarViewController }
		let sidebarView = sidebar?.enclosingScrollView?.superview
		let output = windowBitmap.copy() as! NSBitmapImageRep
		output.size = view.bounds.size
		if let sidebar = sidebar, let sidebarView = sidebarView, let context = NSGraphicsContext(bitmapImageRep: output) {
			let isDark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			NSGraphicsContext.saveGraphicsState()
			NSGraphicsContext.current = context
			NSColor.clear.setFill()
			view.bounds.fill(using: .copy)
			(isDark ? NSColor(calibratedWhite: 0.17, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1)).setFill()
			view.bounds.fill()

			let row = sidebar.selectedRow
			if row >= 0 {
				let rowRect = sidebar.convert(sidebar.rect(ofRow: row), to: nil).insetBy(dx: 10, dy: 0)
				(isDark ? NSColor(calibratedWhite: 1, alpha: 0.12) : NSColor(calibratedWhite: 0, alpha: 0.08)).setFill()
				NSBezierPath(roundedRect: rowRect, xRadius: 6, yRadius: 6).fill()
			}
			// The system selection is drawn with a translucent material too; leave it to the
			// highlight above.
			let style = sidebar.selectionHighlightStyle
			sidebar.selectionHighlightStyle = .none
			// Vibrant appearances (faint headers, dark labels) don't render offscreen either.
			let appearance = sidebarView.appearance
			sidebarView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
			sidebar.reloadData()
			sidebar.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
			for index in 0..<sidebar.numberOfRows {
				if let item = sidebar.item(atRow: index), sidebar.isExpandable(item) {
					sidebar.expandItem(item)
				}
			}
			// Group headers and the version label use vibrant secondary colours that render too
			// dark offscreen; give them a fixed dimmed colour for the capture.
			let dimmed = isDark ? NSColor(calibratedWhite: 1, alpha: 0.45) : NSColor(calibratedWhite: 0, alpha: 0.45)
			var restoreColors: [(NSTextField, NSColor?)] = []
			func dim(_ field: NSTextField) {
				restoreColors.append((field, field.textColor))
				field.textColor = dimmed
			}
			// The group row style recolours header text as it draws, so those are drawn by hand below.
			var headers: [NSTextField] = []
			for index in 0..<sidebar.numberOfRows {
				if let cell = sidebar.view(atColumn: 0, row: index, makeIfNecessary: true) as? NSTableCellView,
				   cell.imageView == nil, let field = cell.textField {
					headers.append(field)
				}
			}
			sidebarView.subviews.compactMap { $0 as? NSTextField }.forEach(dim)
			sidebarView.layoutSubtreeIfNeeded()
			// Caching the sidebar container draws nothing, but its views render one by one.
			let parts: [(NSView, NSRect)] = [(sidebar, sidebar.visibleRect)] + sidebarView.subviews.compactMap { $0 as? NSTextField }.map { ($0, $0.bounds) }
			windowBitmap.draw(in: view.bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
			for (part, rect) in parts {
				guard let bitmap = render(part, rect: rect) else { continue }
				// Clear what the window capture drew there (e.g. the label in the wrong colour) first.
				let target = part.convert(rect, to: nil)
				if part is NSTextField {
					(isDark ? NSColor(calibratedWhite: 0.17, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1)).setFill()
					target.fill()
				}
				bitmap.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
			}
			let background = isDark ? NSColor(calibratedWhite: 0.17, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1)
			for header in headers {
				let rect = header.convert(header.bounds, to: nil)
				background.setFill()
				rect.fill()
				let text = NSAttributedString(string: header.stringValue, attributes: [
					.font: header.font ?? NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
					.foregroundColor: dimmed,
				])
				let size = text.size()
				text.draw(at: NSPoint(x: rect.minX + 2, y: rect.midY - size.height / 2))
			}
			sidebar.selectionHighlightStyle = style
			sidebarView.appearance = appearance
			restoreColors.forEach { $0.0.textColor = $0.1 }
			NSGraphicsContext.restoreGraphicsState()
		}
		try? output.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))

		// Also save each table and outline view on its own, for checking cell contents.
		for (index, table) in tableViews(in: view).enumerated() {
			guard let tableBitmap = table.bitmapImageRepForCachingDisplay(in: table.visibleRect) else { continue }
			table.cacheDisplay(in: table.visibleRect, to: tableBitmap)
			let tablePath = (path as NSString).deletingPathExtension + "-table\(index).png"
			try? tableBitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: tablePath))
		}
	}

	/// Renders at 2x so README screenshots stay sharp on Retina displays.
	private static func render(_ view: NSView, rect: NSRect, scale: CGFloat = 2) -> NSBitmapImageRep? {
		guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width * scale), pixelsHigh: Int(rect.height * scale),
		                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
		                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
		bitmap.size = rect.size
		view.cacheDisplay(in: rect, to: bitmap)
		return bitmap
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
		if ProcessInfo.processInfo.environment["HACKINTOOL_FBTEST"] == "model" {
			modelTest()
		}
		exit(0)
	}

	/// Existing patches must survive quick fixes, and find/replace must match stock bytes.
	private static func modelTest() {
		let savedDVMT = Settings.dvmtPrealloc32MB, savedHDMI = Settings.dpToHDMI
		defer { Settings.dvmtPrealloc32MB = savedDVMT; Settings.dpToHDMI = savedHDMI }
		Settings.dvmtPrealloc32MB = false
		Settings.dpToHDMI = false
		let model = FramebufferModel()
		model.load()
		model.apply(properties: [
			"AAPL,ig-platform-id": Data([0x07, 0x00, 0x9B, 0x3E]),
			"framebuffer-patch-enable": Data([1, 0, 0, 0]),
			"framebuffer-stolenmem": Data([0x00, 0x00, 0x00, 0x02]),
			"framebuffer-con1-enable": Data([1, 0, 0, 0]),
			"framebuffer-con1-type": Data([0x00, 0x08, 0x00, 0x00]),
			"device-id": Data([0x92, 0x3E, 0x00, 0x00]),
		])
		func state(_ label: String) {
			guard let record = model.modified else { return print("\(label): no record") }
			print(String(format: "%@: platform 0x%08X stolen 0x%08X con1 type 0x%X, device-id 0x%04X", label, model.platformID ?? 0, record.stolenMemory ?? 0, record.connector(at: 1).type,
			             model.deviceIDs.indices.contains(model.injectedDeviceIndex) ? model.deviceIDs[model.injectedDeviceIndex] : 0))
		}
		state("loaded (expect stolen 0x02000000, type 0x800, id 0x3E92)")
		Settings.dvmtPrealloc32MB = true
		model.settingsChanged()
		state("DVMT on (expect stolen 0x01300000 = 19 MB)")
		Settings.dvmtPrealloc32MB = false
		model.settingsChanged()
		state("DVMT off (expect stolen back to 0x02000000 from the loaded patch)")
		model.resetChanges()
		Settings.dvmtPrealloc32MB = true
		model.settingsChanged()
		let original = model.original!
		let stock = Data(original.bytes[0..<16])
		var replacement = stock
		replacement[5] ^= 0xFF
		print("find/replace on stock bytes with DVMT on: \(model.findAndReplace(stock, with: replacement)) replacement(s) (expect >= 1)")
	}
}
#endif
