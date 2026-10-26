//
//  DisksViewController.swift
//  Hackintool
//
//  Disks section: EFI partitions (mount, unmount, open) and every partition
//  with its type and usage. The boot EFI is highlighted in green.
//

import Cocoa

final class DisksViewController: NSViewController, SectionContent {
	private let diskList = DiskList()

	private lazy var efiTable = DataTableViewController<Disk>(columns: [
		DataColumn("DeviceName", "Device Name", width: 220, text: { [unowned self] in self.diskList.deviceName(for: $0) })
			.with(image: { $0.icon }),
		DataColumn("VolumeName", "Volume Name", width: 140) { $0.volumeName ?? "" },
		DataColumn("BSDName", "BSD", width: 80, monospaced: true) { $0.bsdName },
		DataColumn("MountPoint", "Mount Point", width: 220) { $0.volumePath?.path ?? "" },
		DataColumn("Actions", "", width: 150) { $0.isMounted ? L("Mounted") : "" }
			.with(customView: { [unowned self] disk in self.actionButtons(for: disk) }),
	])

	private lazy var partitionTable = DataTableViewController<Disk>(columns: [
		DataColumn("VolumeName", "Volume Name", width: 220, text: { [unowned self] in self.partitionName($0) })
			.with(image: { $0.icon }),
		DataColumn("BSDName", "BSD", width: 80, monospaced: true) { $0.bsdName },
		DataColumn("MountPoint", "Mount Point", width: 200) { $0.volumePath?.path ?? "" },
		DataColumn("DiskType", "Disk Type", width: 160) { $0.typeName },
		DataColumn("Size", "Size", width: 90, alignment: .right, sortKey: { .number(Double($0.mediaSize ?? 0)) }) {
			$0.mediaSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? ""
		},
		DataColumn("Usage", "Used", width: 120, sortKey: { disk in .number(disk.usage.map { Double($0.used) / Double($0.total) } ?? -1) }) { disk in
			disk.usage.map { ByteCountFormatter.string(fromByteCount: Int64($0.used), countStyle: .file) } ?? ""
		}.with(customView: { disk in UsageBar.make(fraction: disk.usage.map { Double($0.used) / Double($0.total) }) }),
	])

	private lazy var stacked = StackedTablesViewController(panes: [
		.init(title: "EFI Partitions", viewController: efiTable),
		.init(title: "Partition Scheme", viewController: partitionTable),
	])

	override func loadView() {
		addChild(stacked)
		efiTable.rowColor = { $0.isBootEFI ? .systemGreen : nil }
		efiTable.onDoubleClick = { [weak self] in self?.open($0) }
		partitionTable.rowColor = { $0.typeColor }
		partitionTable.onDoubleClick = { [weak self] in self?.open($0) }
		partitionTable.contextMenuItems = partitionMenuItems()
		view = stacked.view
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		diskList.onChange = { [weak self] in self?.reload() }
	}

	private func reload() {
		efiTable.setRows(diskList.efiPartitions)
		partitionTable.setRows(diskList.disks)
	}

	private func partitionName(_ disk: Disk) -> String {
		if (disk.isAPFS || disk.isAPFSContainer), let link = disk.apfsLink {
			return "🔗 " + link
		}
		if disk.isWholeDisk {
			return diskList.deviceName(for: disk)
		}
		return disk.volumeName ?? ""
	}

	// MARK: SectionContent

	var canRefresh: Bool { return true }
	func refresh() { diskList.recompute() }
	var searchPlaceholder: String? { return L("Search") }

	func search(_ text: String) {
		efiTable.search(text)
		partitionTable.search(text)
	}

	// MARK: Actions

	private func actionButtons(for disk: Disk) -> NSView {
		let mountButton = DiskActionButton(title: L(disk.isMounted ? "Unmount" : "Mount"), disk: disk, target: self, action: #selector(mountButtonClicked(_:)))
		let openButton = DiskActionButton(title: L("Open"), disk: disk, target: self, action: #selector(openFromButton(_:)))
		openButton.isEnabled = disk.isMounted
		let stack = NSStackView(views: [mountButton, openButton])
		stack.spacing = 6
		return stack
	}

	@objc private func mountButtonClicked(_ sender: DiskActionButton) {
		toggleMount(sender.disk)
	}

	@objc private func openFromButton(_ sender: DiskActionButton) {
		open(sender.disk)
	}

	private func toggleMount(_ disk: Disk) {
		DispatchQueue.global(qos: .userInitiated).async {
			disk.isMounted ? disk.unmount() : disk.mount()
		}
	}

	private func open(_ disk: Disk) {
		guard let path = disk.volumePath else { return }
		NSWorkspace.shared.activateFileViewerSelecting([path])
	}

	private var clickedPartition: Disk? {
		return partitionTable.targetRows.first
	}

	private func partitionMenuItems() -> [NSMenuItem] {
		func item(_ title: String, _ action: Selector) -> NSMenuItem {
			let item = NSMenuItem(title: L(title), action: action, keyEquivalent: "")
			item.target = self
			return item
		}
		let copyMenu = NSMenu()
		copyMenu.addItem(item("Volume UUID", #selector(copyVolumeUUID(_:))))
		copyMenu.addItem(item("Volume Path", #selector(copyVolumePath(_:))))
		copyMenu.addItem(item("Media UUID", #selector(copyMediaUUID(_:))))
		let copyItem = NSMenuItem(title: L("Copy to Clipboard"), action: nil, keyEquivalent: "")
		copyItem.submenu = copyMenu

		return [
			item("Mount", #selector(mountClicked(_:))),
			item("Eject", #selector(ejectClicked(_:))),
			item("Open", #selector(openClicked(_:))),
			item("Boot EFI", #selector(bootEFIClicked(_:))),
			.separator(),
			item("Convert to APFS", #selector(convertToAPFSClicked(_:))),
			item("Delete APFS Container", #selector(deleteAPFSContainerClicked(_:))),
			.separator(),
			copyItem,
		]
	}

	@objc private func mountClicked(_ sender: Any?) {
		clickedPartition.map(toggleMount)
	}

	@objc private func ejectClicked(_ sender: Any?) {
		guard let disk = clickedPartition else { return }
		DispatchQueue.global(qos: .userInitiated).async { disk.eject() }
	}

	@objc private func openClicked(_ sender: Any?) {
		clickedPartition.map(open)
	}

	@objc private func bootEFIClicked(_ sender: NSMenuItem) {
		guard let disk = clickedPartition else { return }
		EFIBootDevice.setOverride(disk.isBootEFI && EFIBootDevice.hasOverride ? nil : disk.mediaUUID)
		diskList.recompute()
	}

	@objc private func convertToAPFSClicked(_ sender: Any?) {
		guard let disk = clickedPartition else { return }
		Alerts.confirm(L("Convert %@ to APFS?", disk.bsdName), "The volume is converted in place. Back up your data first.", confirmTitle: "Convert") { confirmed in
			guard confirmed else { return }
			DispatchQueue.global(qos: .userInitiated).async { disk.convertToAPFS() }
		}
	}

	@objc private func deleteAPFSContainerClicked(_ sender: Any?) {
		guard let disk = clickedPartition else { return }
		Alerts.confirm(L("Delete the APFS container %@?", disk.bsdName), "All volumes in the container will be erased.", confirmTitle: "Delete") { confirmed in
			guard confirmed else { return }
			DispatchQueue.global(qos: .userInitiated).async { disk.deleteAPFSContainer() }
		}
	}

	@objc private func copyVolumeUUID(_ sender: Any?) {
		Pasteboard.copy(clickedPartition?.volumeUUID ?? "")
	}

	@objc private func copyVolumePath(_ sender: Any?) {
		Pasteboard.copy(clickedPartition?.volumePath?.path ?? "")
	}

	@objc private func copyMediaUUID(_ sender: Any?) {
		Pasteboard.copy(clickedPartition?.mediaUUID ?? "")
	}
}

extension DisksViewController: NSMenuItemValidation {
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let disk = clickedPartition else { return false }
		switch menuItem.action {
		case #selector(mountClicked(_:)):
			menuItem.title = L(disk.isMounted ? "Unmount" : "Mount")
			return disk.isMountable || disk.isMounted
		case #selector(ejectClicked(_:)):
			return disk.isEjectable && !disk.isInternal
		case #selector(openClicked(_:)):
			return disk.isMounted
		case #selector(bootEFIClicked(_:)):
			menuItem.state = disk.isBootEFI ? .on : .off
			return disk.isEFI
		case #selector(convertToAPFSClicked(_:)):
			return disk.isHFS
		case #selector(deleteAPFSContainerClicked(_:)):
			return disk.isAPFSContainer
		case #selector(copyVolumeUUID(_:)):
			return disk.volumeUUID != nil
		case #selector(copyVolumePath(_:)):
			return disk.volumePath != nil
		case #selector(copyMediaUUID(_:)):
			return disk.mediaUUID != nil
		default:
			return true
		}
	}
}

/// A small in-row button that remembers which disk it acts on.
final class DiskActionButton: NSButton {
	let disk: Disk

	init(title: String, disk: Disk, target: AnyObject, action: Selector) {
		self.disk = disk
		super.init(frame: .zero)
		self.title = title
		self.target = target
		self.action = action
		bezelStyle = .rounded
		controlSize = .small
		font = .systemFont(ofSize: NSFont.smallSystemFontSize)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}
}

extension DataColumn {
	/// Adds an icon before the column's text.
	func with(image: @escaping (Row) -> NSImage?) -> DataColumn {
		var column = self
		column.image = image
		return column
	}

	/// Replaces the column's cell with a custom view.
	func with(customView: @escaping (Row) -> NSView) -> DataColumn {
		var column = self
		column.customView = customView
		return column
	}
}
