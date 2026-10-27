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
	case gpu = "GPU"
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
	case cpu = "CPU"
	case wifi = "WiFi"
	case desktop = "Desktop"
	case laptop = "Laptop"
	case iMac = "IMac"
	case package = "Package"
	case puzzle = "Puzzle"
	case checkCircle = "CheckCircle"
	case warning = "Warning"
	case xCircle = "XCircle"
	case updateCircle = "UpdateCircle"
	case bridge = "Bridge"
	case storage = "Storage"
	case plug = "Plug"
	case shieldLock = "ShieldLock"
	case speaker = "Speaker"
	case keyboard = "Keyboard"

	/// A template image for this symbol, labelled for VoiceOver.
	func image(description: String? = nil, size: CGFloat = 16) -> NSImage {
		// Copy so the size and label don't leak into the shared named image.
		let image = (NSImage(named: "Symbol" + rawValue)?.copy() as? NSImage) ?? NSImage()
		image.size = NSSize(width: size, height: size)
		image.isTemplate = true
		image.accessibilityDescription = description
		return image
	}
}
