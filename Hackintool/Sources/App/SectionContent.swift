//
//  SectionContent.swift
//  Hackintool
//
//  Hooks a section's view controller can adopt so the window toolbar
//  (refresh, search) acts on whatever section is showing.
//

import Cocoa

protocol SectionContent: AnyObject {
	/// Whether the toolbar's refresh button applies to this section.
	var canRefresh: Bool { get }
	func refresh()

	/// Placeholder for the toolbar search field, or nil if the section isn't searchable.
	var searchPlaceholder: String? { get }
	func search(_ text: String)
}

extension SectionContent {
	var canRefresh: Bool { return false }
	func refresh() {}

	var searchPlaceholder: String? { return nil }
	func search(_ text: String) {}
}
