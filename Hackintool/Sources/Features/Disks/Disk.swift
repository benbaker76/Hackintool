//
//  Disk.swift
//  Hackintool
//
//  Disks and partitions from DiskArbitration, kept current by a DA session.
//

import Cocoa
import DiskArbitration
import IOKit.kext

struct Disk {
	/// GPT partition type GUIDs.
	enum PartitionType {
		static let hfsPlus = "48465300-0000-11AA-AA11-00306543ECAC"
		static let fileVault = "53746F72-6167-11AA-AA11-00306543ECAC"
		static let appleAPFS = "7C3457EF-0000-11AA-AA11-00306543ECAC"
		static let apfsVolume = "41504653-0000-11AA-AA11-00306543ECAC"
		static let zfs = "6A898CC3-1DD2-11B2-99A6-080020736631"
		static let apfsContainer1 = "55465300-0000-11AA-AA11-00306543ECAC"
		static let apfsContainer2 = "EF57347C-0000-11AA-AA11-00306543ECAC"
		static let efi = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
		static let windowsRecovery = "DE94BBA4-06D1-4D40-A16A-BFD50179D6AC"
		static let appleRecovery = "426F6F74-0000-11AA-AA11-00306543ECAC"
		static let microsoftReserved = "E3C9E316-0B5C-4DB8-817D-F92DF00215AE"
		static let microsoftBasicData = "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"
		static let appleISC = "69646961-6700-11AA-AA11-00306543ECAC"
		static let appleAPFSRecovery = "52637672-7900-11AA-AA11-00306543ECAC"

		static let names: [String: (name: String, color: NSColor)] = [
			hfsPlus: ("HFS+", .systemRed),
			fileVault: ("FileVault", .systemPink),
			appleAPFS: ("Apple_APFS", .systemOrange),
			apfsVolume: ("APFS Volume", .systemOrange),
			zfs: ("ZFS", .systemYellow),
			apfsContainer1: ("APFS Container", .systemOrange),
			apfsContainer2: ("APFS Container", .systemOrange),
			efi: ("EFI", .systemBrown),
			windowsRecovery: ("Windows Recovery", .systemPurple),
			appleRecovery: ("Apple Recovery", .systemPurple),
			microsoftReserved: ("Microsoft Reserved", .systemPurple),
			microsoftBasicData: ("Microsoft Basic Data", .systemGray),
			appleISC: ("Apple_APFS_ISC", .systemOrange),
			appleAPFSRecovery: ("Apple_APFS_Recovery", .systemPurple),
		]
	}

	let bsdName: String
	let mediaName: String?
	let mediaUUID: String?
	let mediaContent: String?
	let mediaSize: UInt64?
	let mediaIcon: [String: Any]?
	let deviceModel: String?
	let busName: String?
	let volumeKind: String?
	let volumeName: String?
	let volumePath: URL?
	let volumeType: String?
	let volumeUUID: String?
	let isMountable: Bool
	let isNetworkVolume: Bool
	let isWholeMedia: Bool
	let isLeaf: Bool
	let isWritable: Bool
	let isEjectable: Bool
	let isRemovable: Bool
	let isInternal: Bool

	/// Set by DiskList: the EFI partition this Mac booted from.
	var isBootEFI = false
	/// For APFS containers, the physical store's BSD name and vice versa.
	var apfsLink: String?

	init?(description: [String: Any]) {
		guard let bsdName = description[kDADiskDescriptionMediaBSDNameKey as String] as? String else { return nil }
		func flag(_ key: CFString) -> Bool { return (description[key as String] as? Bool) ?? false }
		func uuid(_ key: CFString) -> String? {
			guard let value = description[key as String] else { return nil }
			return CFUUIDCreateString(nil, (value as! CFUUID)) as String?
		}

		self.bsdName = bsdName
		mediaName = description[kDADiskDescriptionMediaNameKey as String] as? String
		mediaUUID = uuid(kDADiskDescriptionMediaUUIDKey)
		mediaContent = description[kDADiskDescriptionMediaContentKey as String] as? String
		mediaSize = (description[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.uint64Value
		mediaIcon = description[kDADiskDescriptionMediaIconKey as String] as? [String: Any]
		deviceModel = (description[kDADiskDescriptionDeviceModelKey as String] as? String)?.trimmingCharacters(in: .whitespaces)
		busName = description[kDADiskDescriptionBusNameKey as String] as? String
		volumeKind = description[kDADiskDescriptionVolumeKindKey as String] as? String
		volumeName = description[kDADiskDescriptionVolumeNameKey as String] as? String
		volumePath = description[kDADiskDescriptionVolumePathKey as String] as? URL
		volumeType = description[kDADiskDescriptionVolumeTypeKey as String] as? String
		volumeUUID = uuid(kDADiskDescriptionVolumeUUIDKey)
		isMountable = flag(kDADiskDescriptionVolumeMountableKey)
		isNetworkVolume = flag(kDADiskDescriptionVolumeNetworkKey)
		isWholeMedia = flag(kDADiskDescriptionMediaWholeKey)
		isLeaf = flag(kDADiskDescriptionMediaLeafKey)
		isWritable = flag(kDADiskDescriptionMediaWritableKey)
		isEjectable = flag(kDADiskDescriptionMediaEjectableKey)
		isRemovable = flag(kDADiskDescriptionMediaRemovableKey)
		isInternal = flag(kDADiskDescriptionDeviceInternalKey)
	}

	// MARK: Identity

	/// "disk2s1" → (2, 1); "disk2" → (2, nil).
	var deviceAndSlice: (device: Int, slice: Int?) {
		let parts = bsdName.dropFirst(4).split(separator: "s", maxSplits: 1)
		return (Int(parts.first ?? "") ?? 0, parts.count > 1 ? Int(parts[1]) : nil)
	}

	/// The whole disk this partition is on, e.g. "disk2".
	var wholeDiskName: String {
		return "disk\(deviceAndSlice.device)"
	}

	var isWholeDisk: Bool { return deviceAndSlice.slice == nil }

	/// Sorts disk0, disk0s1, disk0s2, disk1...
	var sortKey: Double {
		let (device, slice) = deviceAndSlice
		return Double(device * 1000 + (slice ?? 0))
	}

	var isMounted: Bool { return volumePath != nil }
	var isHFS: Bool { return volumeKind == "hfs" }
	var isEFI: Bool { return mediaContent == PartitionType.efi }
	var isAPFS: Bool { return mediaContent == PartitionType.appleAPFS }
	var isAPFSContainer: Bool { return mediaContent == PartitionType.apfsContainer1 || mediaContent == PartitionType.apfsContainer2 }

	var typeName: String {
		return mediaContent.flatMap { PartitionType.names[$0]?.name ?? $0 } ?? ""
	}

	var typeColor: NSColor? {
		if isBootEFI {
			return .systemGreen
		}
		return mediaContent.flatMap { PartitionType.names[$0]?.color }
	}

	/// Used and total bytes of the mounted volume.
	var usage: (used: UInt64, total: UInt64)? {
		guard let path = volumePath?.path,
		      let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path),
		      let total = (attributes[.systemSize] as? NSNumber)?.uint64Value, total > 0,
		      let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value else { return nil }
		return (total - min(free, total), total)
	}

	/// The volume's custom icon, or the driver-provided media icon.
	var icon: NSImage? {
		if let path = volumePath {
			let iconURL = path.appendingPathComponent(".VolumeIcon.icns")
			if let image = NSImage(contentsOf: iconURL) {
				return image
			}
			return NSWorkspace.shared.icon(forFile: path.path)
		}
		guard let bundleID = mediaIcon?[kCFBundleIdentifierKey as String] as? String,
		      let resource = mediaIcon?[kIOBundleResourceFileKey] as? String,
		      let kextURL = Kexts.url(forBundleIdentifier: bundleID),
		      let path = Bundle(url: kextURL)?.path(forResource: resource, ofType: nil) else { return nil }
		return NSImage(contentsOfFile: path)
	}

	// MARK: Actions (run as root through diskutil)

	/// Runs diskutil as root, showing its message if it fails.
	private func diskutil(_ arguments: [String]) {
		guard let result = Privileges.shared.run("/usr/sbin/diskutil", arguments) else { return }
		if !result.succeeded {
			Alerts.error(result.message)
		}
	}

	func mount() { diskutil(["mount", "/dev/" + bsdName]) }
	func unmount() { diskutil(["unmount", "/dev/" + bsdName]) }
	func eject() { diskutil(["eject", "/dev/" + bsdName]) }
	func convertToAPFS() { diskutil(["apfs", "convert", bsdName]) }
	func deleteAPFSContainer() { diskutil(["apfs", "deleteContainer", bsdName]) }
}

/// Watches DiskArbitration and keeps a sorted list of disks.
final class DiskList {
	private(set) var disks: [Disk] = []
	var onChange: (() -> Void)?

	private let session: DASession?
	/// Disks arrive one callback at a time; recompute once they settle.
	private let debouncer = Debouncer(delay: 0.2)

	init() {
		session = DASessionCreate(kCFAllocatorDefault)
		guard let session = session else { return }
		let context = Unmanaged.passUnretained(self).toOpaque()

		DARegisterDiskAppearedCallback(session, nil, { disk, context in
			DiskList.from(context)?.update(disk)
		}, context)
		DARegisterDiskDisappearedCallback(session, nil, { disk, context in
			DiskList.from(context)?.remove(disk)
		}, context)
		DARegisterDiskDescriptionChangedCallback(session, nil, nil, { disk, _, context in
			DiskList.from(context)?.update(disk)
		}, context)
		DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
	}

	deinit {
		if let session = session {
			DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
		}
	}

	private static func from(_ context: UnsafeMutableRawPointer?) -> DiskList? {
		guard let context = context else { return nil }
		return Unmanaged<DiskList>.fromOpaque(context).takeUnretainedValue()
	}

	var efiPartitions: [Disk] {
		return disks.filter { $0.isEFI }
	}

	/// The whole disk's name, for labelling partitions ("Samsung SSD 970").
	func deviceName(for disk: Disk) -> String {
		let whole = disks.first { $0.bsdName == disk.wholeDiskName }
		return whole?.mediaName ?? whole?.deviceModel ?? ""
	}

	private func update(_ daDisk: DADisk) {
		guard let description = DADiskCopyDescription(daDisk) as? [String: Any], let disk = Disk(description: description) else { return }
		if let index = disks.firstIndex(where: { $0.bsdName == disk.bsdName }) {
			disks[index] = disk
		} else {
			disks.append(disk)
		}
		didChange()
	}

	private func remove(_ daDisk: DADisk) {
		guard let name = DADiskGetBSDName(daDisk).map({ String(cString: $0) }) else { return }
		disks.removeAll { $0.bsdName == name }
		didChange()
	}

	private func didChange() {
		debouncer.schedule { [weak self] in self?.recompute() }
	}

	/// Re-sorts, marks the boot EFI and links APFS containers to their physical stores.
	func recompute() {
		disks.sort { $0.sortKey < $1.sortKey }
		let bootUUID = EFIBootDevice.mediaUUID
		for index in disks.indices {
			disks[index].isBootEFI = false
			disks[index].apfsLink = nil
		}
		if let bootUUID = bootUUID, let bootDisk = disks.first(where: { $0.mediaUUID == bootUUID }) {
			// The boot device may be the EFI partition itself or another partition on the same disk.
			let efiIndex = bootDisk.isEFI
				? disks.firstIndex { $0.bsdName == bootDisk.bsdName }
				: disks.firstIndex { $0.isEFI && $0.wholeDiskName == bootDisk.wholeDiskName }
			if let efiIndex = efiIndex {
				disks[efiIndex].isBootEFI = true
			}
		}
		for index in disks.indices where disks[index].isAPFSContainer {
			guard let uuid = disks[index].mediaUUID, let store = APFS.physicalStoreBSDName(containerUUID: uuid) else { continue }
			disks[index].apfsLink = store
			if let storeIndex = disks.firstIndex(where: { $0.bsdName == store }) {
				disks[storeIndex].apfsLink = disks[index].bsdName
			}
		}
		onChange?()
	}
}

enum APFS {
	/// The BSD name of the partition holding an APFS container.
	static func physicalStoreBSDName(containerUUID: String) -> String? {
		for container in IORegistryEntry.services(matching: "AppleAPFSContainer") where container.string("UUID") == containerUUID {
			// The container's own media (AppleAPFSMedia) is an IOMedia subclass, so match the class exactly.
			return container.ancestors().first { $0.className == "IOMedia" }?.string("BSD Name")
		}
		return nil
	}
}

/// Works out which partition the bootloader started from.
enum EFIBootDevice {
	private static let overrideKey = "EFIBootDeviceUUID"

	/// A user's explicit choice (Disks ▸ Boot EFI), otherwise the bootloader log,
	/// NVRAM efi-boot-device, or IODeviceTree:/chosen.
	static var mediaUUID: String? {
		if let override = UserDefaults.standard.string(forKey: overrideKey) {
			return override
		}
		return fromBootLog() ?? fromNVRAM() ?? Machine.shared.bootDevicePath
	}

	static var hasOverride: Bool {
		return UserDefaults.standard.string(forKey: overrideKey) != nil
	}

	static func setOverride(_ uuid: String?) {
		UserDefaults.standard.set(uuid, forKey: overrideKey)
	}

	/// From "SelfDevicePath=...\HD(1,GPT,<UUID>,0x28,0x64000)" in the bootloader log.
	static func fromBootLog() -> String? {
		guard let log = BootLog.bootloaderLog(),
		      let line = log.components(separatedBy: CharacterSet(charactersIn: "\r\n")).first(where: { $0.contains("SelfDevicePath=") }),
		      let hdRange = line.range(of: "HD(") else { return nil }
		let fields = line[hdRange.upperBound...].split(separator: ",")
		return fields.count >= 3 ? String(fields[2]) : nil
	}

	/// The UUID in the IOPropertyMatch of NVRAM efi-boot-device (an XML plist fragment).
	static func fromNVRAM() -> String? {
		guard let data = IORegistryEntry(path: "IODeviceTree:/options")?.data("efi-boot-device"),
		      let text = String(data: data.prefix { $0 != 0 }, encoding: .ascii),
		      let document = try? XMLDocument(xmlString: "<root>\(text)</root>", options: []),
		      let node = try? document.nodes(forXPath: "//key[text()='IOPropertyMatch']/following-sibling::dict[1]/key[text()='UUID']/following-sibling::string[1]").first else { return nil }
		return node.stringValue
	}
}
