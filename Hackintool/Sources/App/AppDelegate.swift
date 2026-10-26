//
//  AppDelegate.swift
//  Hackintool
//
//  Created by Ben Baker on 6/19/18.
//  Copyright (c) 2018 Ben Baker. All rights reserved.
//

import Cocoa
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
	private(set) var mainWindowController: MainWindowController?

	/// Sparkle reads the feed URL and public key from Info.plist (SUFeedURL, SUPublicEDKey).
	let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

	func applicationWillFinishLaunching(_ notification: Notification) {
		NSApp.mainMenu = MainMenu.make(updater: updaterController)
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		let windowController = MainWindowController()
		mainWindowController = windowController
		windowController.showWindow(nil)
		windowController.window?.center()
		#if DEBUG
		DebugSnapshot.runIfRequested(windowController)
		#endif
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		return true
	}
}
