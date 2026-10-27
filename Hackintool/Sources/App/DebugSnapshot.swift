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

		// "usb" or "framebuffer:1" for a section's second page.
		let sections: [(section: Section, page: Int?)] = environment["HACKINTOOL_SNAPSHOT_SECTIONS"]?
			.split(separator: ",").compactMap { item -> (Section, Int?)? in
				let parts = item.split(separator: ":")
				guard let section = Section(rawValue: String(parts[0])) else { return nil }
				return (section, parts.count > 1 ? Int(parts[1]) : nil)
			} ?? Section.allCases.map { ($0, nil) }
		// Light by default: cacheDisplay draws onto white, so dark-mode text would vanish.
		NSApp.appearance = NSAppearance(named: environment["HACKINTOOL_SNAPSHOT_APPEARANCE"] == "dark" ? .darkAqua : .aqua)
		try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

		var remaining = sections
		func next() {
			guard let (section, page) = remaining.first else {
				NSApp.terminate(nil)
				return
			}
			remaining.removeFirst()
			windowController.show(section)
			if let page = page, let tabs = tabbedViewController(in: windowController.window?.contentViewController) {
				tabs.select(pageAt: page)
			}
			// Give the section time to load its data and lay out.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
				save(windowController.window, to: "\(directory)/\(section.rawValue)\(page.map { "-page\($0)" } ?? "").png")
				next()
			}
		}
		next()
	}

	/// The outermost tabbed page controller on screen.
	private static func tabbedViewController(in viewController: NSViewController?) -> TabbedViewController? {
		guard let viewController = viewController else { return nil }
		if let tabs = viewController as? TabbedViewController {
			return tabs
		}
		return viewController.children.lazy.compactMap(tabbedViewController(in:)).first
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

#if DEBUG
/// HACKINTOOL_AMDTEST=/path/to/patches.plist: exercise the AMD Vanilla merge and checks, then quit.
enum AMDVanillaSelfTest {
	static func runIfRequested() {
		guard let path = ProcessInfo.processInfo.environment["HACKINTOOL_AMDTEST"] else { return }
		var failures = 0
		func check(_ condition: Bool, _ message: String) {
			print((condition ? "PASS " : "FAIL ") + message)
			if !condition { failures += 1 }
		}
		guard let data = FileManager.default.contents(atPath: path), let patches = AMDVanilla.parse(data) else {
			print("FAIL couldn't parse \(path)")
			exit(1)
		}
		for patch in patches {
			print(String(format: "  %2d %@ %-16@ %@", patch.index, patch.isEnabledByDefault ? "on " : "off", patch.macOSRange, patch.comment))
		}
		print("  newest macOS: \(AMDVanilla.newestMacOS(patches) ?? "?"), running covered: \(AMDVanilla.isRunningKernelCovered(patches))")
		print("  PAT groups: \(AMDVanilla.exclusiveGroups(patches).map { $0.map { $0.index } })")
		let defaults = Set(patches.filter { $0.isEnabledByDefault }.map { $0.index })
		let corePatches = patches.filter { $0.kind == .coreCount }
		check(corePatches.count == 4, "four core count patches")

		// A new config.
		let fresh = ConfigPlist(format: .openCore)
		AMDVanilla.apply(patches, enabled: defaults, coreCount: 8, provideCurrentCpuInfo: true, to: fresh)
		let freshPatches = fresh.kernelPatches().compactMap { $0 as? NSDictionary }
		check(freshPatches.count == patches.count, "fresh config has \(patches.count) patches")
		check(freshPatches.filter { $0["Comment"] as? String == corePatches[0].comment }.allSatisfy { ($0["Replace"] as! Data)[1] == 8 }, "core count byte is 8")
		check(fresh.kernelQuirks["ProvideCurrentCpuInfo"] as? Bool == true, "ProvideCurrentCpuInfo enabled")
		let freshReport = AMDVanillaReport(config: fresh.root, patches: patches)
		check(freshReport.warnings.isEmpty, "fresh report has no warnings: \(freshReport.warnings)")
		check(freshReport.coreCounts == [8], "report reads core count 8")
		check(patches.allSatisfy { if case .current(let on) = freshReport.states[$0.index]! { return on == defaults.contains($0.index) } else { return false } }, "every patch current with default enablement")

		// An existing config: another patch first, an outdated AMD patch, both PAT patches on, core count 0, no quirk.
		let existing = ConfigPlist(format: .openCore)
		let other: NSMutableDictionary = ["Comment": "Someone else's patch", "Identifier": "com.example", "Enabled": true, "Find": Data([1]), "Replace": Data([2])]
		let array = existing.kernelPatches()
		array.add(other)
		for patch in patches {
			let entry = patch.configEntry(enabled: patch.kind == .pat ? true : patch.isEnabledByDefault, coreCount: 0)
			if patch.index == 5 { entry["Find"] = Data([0xDE, 0xAD]) }
			array.add(entry)
		}
		let report = AMDVanillaReport(config: existing.root, patches: patches)
		print("  warnings: \(report.warnings)")
		check(report.warnings.count == 5, "warns about quirk, core count 0, PAT and outdated")
		if case .outdated? = report.states[5] { check(true, "patch 5 outdated") } else { check(false, "patch 5 outdated") }

		AMDVanilla.apply(patches, enabled: defaults, coreCount: 12, provideCurrentCpuInfo: true, to: existing)
		let merged = existing.kernelPatches().compactMap { $0 as? NSDictionary }
		check(merged.count == patches.count + 1, "merge replaced rather than duplicated (\(merged.count))")
		check(merged.first?["Comment"] as? String == "Someone else's patch", "other patch kept in place")
		let mergedReport = AMDVanillaReport(config: existing.root, patches: patches)
		check(mergedReport.warnings.isEmpty, "merged report clean: \(mergedReport.warnings)")
		check(mergedReport.coreCounts == [12], "core count now 12")

		// Round trip through a file.
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("amdtest-config.plist")
		try? existing.write(to: url)
		let reread = ConfigPlist(contentsOf: url, format: .openCore)
		check(reread.map { AMDVanillaReport(config: $0.root, patches: patches).warnings.isEmpty } == true, "written file reads back clean")

		for (kernel, expected) in [("17.0.0", "10.13"), ("18.99.99", "10.14"), ("20.3.0", "11.2"), ("22.4.0", "13.3"), ("22.3.99", "13.2"), ("25.99.99", "26"), ("27.0.0", "27")] {
			check(AMDVanilla.macOSVersion(forKernel: kernel) == expected, "\(kernel) → \(AMDVanilla.macOSVersion(forKernel: kernel) ?? "nil") (want \(expected))")
		}
		print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
		exit(failures == 0 ? 0 : 1)
	}
}
#endif

#if DEBUG
/// HACKINTOOL_RADEONTEST=1: classify every AMD GPU in pci.ids and check the generated config, then quit.
enum RadeonSelfTest {
	static func runIfRequested() {
		guard ProcessInfo.processInfo.environment["HACKINTOOL_RADEONTEST"] != nil else { return }
		var failures = 0
		func check(_ condition: Bool, _ message: String) {
			print((condition ? "PASS " : "FAIL ") + message)
			if !condition { failures += 1 }
		}
		let database = IDDatabase.pci
		database.loadIfNeeded()
		var counts: [String: Int] = [:]
		var unknown: [String] = []
		for deviceID in UInt32(0)...0xFFFF {
			guard let name = database.deviceName(vendorID: PCIVendor.amd, deviceID: deviceID),
			      !name.contains("Audio"), !name.contains("HDMI"), !name.contains("USB"), !name.contains("Bridge") else { continue }
			let family = RadeonFamily.family(forDeviceName: name)
			counts[family.name, default: 0] += 1
			if family == .unknown { unknown.append(String(format: "%04x %@", deviceID, name)) }
		}
		counts.sorted { $0.key < $1.key }.forEach { print("  \($0.key): \($0.value)") }
		print("  unknown sample: \(unknown.filter { ($0.contains("Radeon") || $0.contains("FirePro")) && !$0.contains(" RV") && !$0.contains(" R3") && !$0.contains(" R4") && !$0.contains(" R5") && !$0.contains(" RS") && !$0.contains(" M") }.prefix(60).joined(separator: "\n    "))")

		let expectations: [(UInt32, RadeonFamily)] = [
			(0x73BF, .navi21), (0x73FF, .navi23), (0x731F, .navi1x), (0x7340, .navi1x), (0x73DF, .unsupportedDiscrete),
			(0x744C, .unsupportedDiscrete), (0x67DF, .polaris), (0x699F, .lexa), (0x694E, .polaris22), (0x687F, .vega),
			(0x66AF, .vega), (0x6798, .gcn1), (0x683F, .gcn1), (0x67B1, .gcn2), (0x7300, .gcn3), (0x15DD, .vegaAPU),
			(0x15D8, .vegaAPU), (0x1636, .vegaAPU), (0x1638, .vegaAPU), (0x164C, .vegaAPU), (0x15E7, .vegaAPU),
			(0x1681, .unsupportedAPU), (0x15BF, .unsupportedAPU), (0x164E, .unsupportedAPU), (0x1900, .unsupportedAPU), (0x1309, .unsupportedAPU),
		]
		for (deviceID, expected) in expectations {
			let gpu = RadeonGPU.manual(deviceID: deviceID, devicePath: "PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)")
			check(gpu.family == expected, String(format: "0x%04X %@ → %@", deviceID, gpu.name, gpu.family.name))
		}

		// Navi: agdpmod on by default, null terminated.
		let navi = RadeonGPU.manual(deviceID: 0x73BF, devicePath: "PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)/Pci(0x0,0x0)/Pci(0x0,0x0)")
		var options = RadeonOptions(for: navi)
		check(options.properties()["agdpmod"] as? Data == Data("pikera\0".utf8), "Navi gets agdpmod=pikera\\0")
		options.shikigva = 80
		options.model = "AMD Radeon RX 6900 XT"
		let config = ConfigPlist(format: .openCore)
		config.bootArgs = "-v keepsyms=1 radpg=7"
		var cape = RadeonOptions(for: RadeonGPU.manual(deviceID: 0x683F, devicePath: ""))
		check(cape.radPG15, "Cape Verde defaults to radpg=15")
		cape.radDVI = true
		RadeonConfig.apply(path: navi.devicePath, options: options, to: config)
		config.addBootArgs(cape.bootArgs)
		let props = config.deviceProperties[navi.devicePath] as? NSDictionary
		check(props?["shikigva"] as? Data == Data([80, 0, 0, 0]), "shikigva 80 as 4-byte little endian")
		check(props?["model"] as? String == "AMD Radeon RX 6900 XT", "model string")
		check(config.bootArgs == "-v keepsyms=1 radpg=15 -raddvi", "boot-args merged: \(config.bootArgs)")
		let delete = (((config.root["NVRAM"] as? NSDictionary)?["Delete"] as? NSDictionary)?[ConfigPlist.appleBootVariableGUID] as? NSArray)
		check(delete?.contains("boot-args") == true, "boot-args listed under NVRAM Delete")

		// Unsupported: only disable-gpu.
		var navi22 = RadeonOptions(for: RadeonGPU.manual(deviceID: 0x73DF, devicePath: ""))
		navi22.model = "ignored"
		check(navi22.properties().keys.sorted() == ["disable-gpu"], "unsupported card writes only disable-gpu")

		let clover = ConfigPlist(format: .clover)
		clover.addBootArgs(["-raddvi"])
		check(((clover.root["Boot"] as? NSDictionary)?["Arguments"] as? String) == "-raddvi", "Clover boot-args in Boot ▸ Arguments")
		print(RadeonConfig.preview(path: navi.devicePath, options: options, format: .openCore))
		print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
		exit(failures == 0 ? 0 : 1)
	}
}
#endif
