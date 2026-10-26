//
//  Kexts.swift
//  Hackintool
//
//  Locating loaded kernel extensions.
//

import Cocoa
import IOKit.kext

enum Kexts {
	/// The on-disk location of a loaded kext, from its bundle identifier.
	static func url(forBundleIdentifier bundleID: String) -> URL? {
		return KextManagerCreateURLForBundleIdentifier(kCFAllocatorDefault, bundleID as CFString)?.takeRetainedValue() as URL?
	}

	/// Reveals a kext in Finder. Returns false if it can't be found.
	@discardableResult
	static func reveal(bundleIdentifier bundleID: String?) -> Bool {
		guard let bundleID = bundleID, let url = url(forBundleIdentifier: bundleID) else {
			NSSound.beep()
			return false
		}
		NSWorkspace.shared.activateFileViewerSelecting([url])
		return true
	}
}
