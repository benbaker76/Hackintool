//
//  MainMenu.swift
//  Hackintool
//
//  The menu bar. Section-specific commands use nil-targeted actions; the main
//  window controller forwards them to the section that's showing.
//

import Cocoa
import Sparkle

enum MainMenu {
	static func make(updater: SPUStandardUpdaterController) -> NSMenu {
		let mainMenu = NSMenu()
		mainMenu.addItem(submenuItem(appMenu(updater: updater)))
		mainMenu.addItem(submenuItem(fileMenu()))
		mainMenu.addItem(submenuItem(editMenu()))
		mainMenu.addItem(submenuItem(viewMenu()))

		let windowMenu = self.windowMenu()
		mainMenu.addItem(submenuItem(windowMenu))
		NSApp.windowsMenu = windowMenu

		let helpMenu = self.helpMenu()
		mainMenu.addItem(submenuItem(helpMenu))
		NSApp.helpMenu = helpMenu
		return mainMenu
	}

	// MARK: Menus

	private static func appMenu(updater: SPUStandardUpdaterController) -> NSMenu {
		let menu = NSMenu(title: "Hackintool")
		menu.addItem(item(L("About Hackintool"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
		menu.addItem(item(L("Check for Updates..."), #selector(SPUStandardUpdaterController.checkForUpdates(_:)), target: updater))
		menu.addItem(.separator())

		let servicesMenu = NSMenu(title: L("Services"))
		menu.addItem(submenuItem(servicesMenu))
		NSApp.servicesMenu = servicesMenu
		menu.addItem(.separator())

		menu.addItem(item(L("Hide Hackintool"), #selector(NSApplication.hide(_:)), key: "h"))
		menu.addItem(item(L("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]))
		menu.addItem(item(L("Show All"), #selector(NSApplication.unhideAllApplications(_:))))
		menu.addItem(.separator())
		menu.addItem(item(L("Quit Hackintool"), #selector(NSApplication.terminate(_:)), key: "q"))
		return menu
	}

	private static func fileMenu() -> NSMenu {
		let menu = NSMenu(title: L("File"))
		menu.addItem(item(L("Close"), #selector(NSWindow.performClose(_:)), key: "w"))
		return menu
	}

	private static func editMenu() -> NSMenu {
		let menu = NSMenu(title: L("Edit"))
		menu.addItem(item(L("Undo"), Selector(("undo:")), key: "z"))
		menu.addItem(item(L("Redo"), Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
		menu.addItem(.separator())
		menu.addItem(item(L("Cut"), #selector(NSText.cut(_:)), key: "x"))
		menu.addItem(item(L("Copy"), #selector(NSText.copy(_:)), key: "c"))
		menu.addItem(item(L("Paste"), #selector(NSText.paste(_:)), key: "v"))
		menu.addItem(item(L("Delete"), #selector(NSText.delete(_:))))
		menu.addItem(item(L("Select All"), #selector(NSText.selectAll(_:)), key: "a"))
		menu.addItem(.separator())
		menu.addItem(item(L("Find…"), #selector(MainWindowController.focusSearch(_:)), key: "f"))
		return menu
	}

	private static func viewMenu() -> NSMenu {
		let menu = NSMenu(title: L("View"))
		menu.addItem(item(L("Show Sidebar"), #selector(NSSplitViewController.toggleSidebar(_:)), key: "s", modifiers: [.command, .control]))
		menu.addItem(item(L("Refresh"), #selector(MainWindowController.refresh(_:)), key: "r"))
		menu.addItem(.separator())

		// ⌘1–⌘9 jump to the first nine sections.
		for (index, section) in Section.allCases.enumerated() {
			let sectionItem = item(section.title, #selector(MainWindowController.showSection(_:)), key: index < 9 ? String(index + 1) : "")
			sectionItem.representedObject = section.rawValue
			menu.addItem(sectionItem)
		}
		menu.addItem(.separator())
		menu.addItem(item(L("Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control]))
		return menu
	}

	private static func windowMenu() -> NSMenu {
		let menu = NSMenu(title: L("Window"))
		menu.addItem(item(L("Minimize"), #selector(NSWindow.performMiniaturize(_:)), key: "m"))
		menu.addItem(item(L("Zoom"), #selector(NSWindow.performZoom(_:))))
		menu.addItem(.separator())
		menu.addItem(item(L("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:))))
		return menu
	}

	private static func helpMenu() -> NSMenu {
		let menu = NSMenu(title: L("Help"))
		menu.addItem(item(L("Hackintool Help"), #selector(NSApplication.showHelp(_:)), key: "?"))
		return menu
	}

	// MARK: Helpers

	static func item(_ title: String, _ action: Selector?, key: String = "", modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
		item.keyEquivalentModifierMask = modifiers
		item.target = target
		return item
	}

	static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
		let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
		item.submenu = menu
		return item
	}
}
