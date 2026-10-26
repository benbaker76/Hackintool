//
//  Section.swift
//  Hackintool
//
//  The top-level areas of the app, as listed in the sidebar.
//

import Cocoa

enum Section: String, CaseIterable {
	case system
	case framebuffer
	case displays
	case sound
	case usb
	case disks
	case pci
	case power
	case bootloader
	case nvram
	case extensions
	case utilities
	case calculator
	case logs

	enum Group: CaseIterable {
		case mac, graphics, hardware, boot, tools

		var title: String {
			switch self {
			case .mac: return L("Mac")
			case .graphics: return L("Graphics")
			case .hardware: return L("Hardware")
			case .boot: return L("Boot")
			case .tools: return L("Tools")
			}
		}

		var sections: [Section] {
			return Section.allCases.filter { $0.group == self }
		}
	}

	var group: Group {
		switch self {
		case .system: return .mac
		case .framebuffer, .displays: return .graphics
		case .sound, .usb, .disks, .pci, .power: return .hardware
		case .bootloader, .nvram, .extensions: return .boot
		case .utilities, .calculator, .logs: return .tools
		}
	}

	var title: String {
		switch self {
		case .system: return L("System")
		case .framebuffer: return L("Patch")
		case .displays: return L("Displays")
		case .sound: return L("Sound")
		case .usb: return L("USB")
		case .disks: return L("Disks")
		case .pci: return L("PCIe")
		case .power: return L("Power")
		case .bootloader: return L("Bootloader")
		case .nvram: return L("NVRAM")
		case .extensions: return L("Extensions")
		case .utilities: return L("Utilities")
		case .calculator: return L("Calc")
		case .logs: return L("Logs")
		}
	}

	var symbol: Symbol {
		switch self {
		case .system: return .system
		case .framebuffer: return .framebuffer
		case .displays: return .displays
		case .sound: return .sound
		case .usb: return .usb
		case .disks: return .disks
		case .pci: return .pci
		case .power: return .power
		case .bootloader: return .boot
		case .nvram: return .nvram
		case .extensions: return .extensions
		case .utilities: return .utilities
		case .calculator: return .calculator
		case .logs: return .logs
		}
	}

	func makeViewController() -> NSViewController {
		switch self {
		case .system: return SystemViewController()
		case .pci: return PCIViewController()
		case .calculator: return CalculatorViewController()
		case .power: return PowerViewController()
		case .nvram: return NVRAMViewController()
		case .logs: return LogsViewController()
		case .disks: return DisksViewController()
		case .bootloader: return BootloaderViewController()
		case .extensions: return ExtensionsViewController()
		case .utilities: return UtilitiesViewController()
		case .sound: return SoundViewController()
		case .usb: return USBViewController()
		case .displays: return DisplaysViewController()
		case .framebuffer: return FramebufferViewController()
		}
	}
}
