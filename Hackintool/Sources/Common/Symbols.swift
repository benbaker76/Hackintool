//
//  Symbols.swift
//  Hackintool
//
//  Outline icons (Tabler) stored as template images in Symbols.xcassets.
//  They tint with the system appearance and look the same on every macOS version.
//

import Cocoa

enum Symbol: String {
	case system = "System"
	case framebuffer = "Framebuffer"
	case boot = "Boot"
	case nvram = "NVRAM"
	case extensions = "Extensions"
	case displays = "Displays"
	case sound = "Sound"
	case usb = "USB"
	case disks = "Disks"
	case pci = "PCI"
	case power = "Power"
	case calculator = "Calculator"
	case utilities = "Utilities"
	case logs = "Logs"
	case lock = "Lock"
	case unlock = "Unlock"
	case refresh = "Refresh"
	case search = "Search"
	case copy = "Copy"
	case export = "Export"
	case `import` = "Import"
	case folder = "Folder"
	case trash = "Trash"
	case add = "Add"
	case remove = "Remove"
	case info = "Info"
	case terminal = "Terminal"
	case web = "Web"
	case network = "Network"
	case bluetooth = "Bluetooth"
	case wand = "Wand"
	case heart = "Heart"
	case gitHub = "GitHub"
	case settings = "Settings"

	/// A template image for this symbol, labelled for VoiceOver.
	func image(description: String? = nil) -> NSImage {
		// Copy so the accessibility label doesn't leak into the shared named image.
		let image = (NSImage(named: "Symbol" + rawValue)?.copy() as? NSImage) ?? NSImage()
		image.isTemplate = true
		image.accessibilityDescription = description
		return image
	}
}
