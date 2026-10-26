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
		Settings.migrateLegacySettings()
		#if DEBUG
		FramebufferSelfTest.runIfRequested()
		AMDVanillaSelfTest.runIfRequested()
		#endif
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

	/// File ▸ Generate Audio Codecs Info: rebuilds Audio/Codecs.plist from AppleALC's Resources folder.
	@objc func generateAudioCodecsInfo(_ sender: Any?) {
		let panel = NSOpenPanel()
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.message = L("Select AppleALC Resources Folder")
		guard let window = NSApp.mainWindow else { return }
		panel.beginSheetModal(for: window) { response in
			guard response == .OK, let folder = panel.url else { return }
			let codecs = AudioCodecCatalog.generate(fromAppleALCResources: folder)
			guard !codecs.isEmpty else {
				Alerts.error("No codecs found.", folder.path)
				return
			}
			FilePanels.save(suggestedName: "Codecs.plist", allowedExtensions: ["plist"]) { url in
				(codecs as NSArray).write(to: url, atomically: true)
			}
		}
	}
}
