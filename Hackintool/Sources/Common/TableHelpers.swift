//
//  TableHelpers.swift
//  Hackintool
//
//  Shared pieces for building table and outline views in code.
//

import Cocoa

enum ScrollingTable {
	/// Embeds a table in a scroll view and returns the scroll view.
	static func wrap(_ tableView: NSTableView) -> NSScrollView {
		let scrollView = NSScrollView()
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.borderType = .noBorder
		return scrollView
	}
}

/// A plain text cell, reused through the table's identifier queue.
enum TextCell {
	static func make(in tableView: NSTableView, identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
		if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
			return cell
		}
		let cell = NSTableCellView()
		cell.identifier = identifier
		let textField = NSTextField(labelWithString: "")
		textField.lineBreakMode = .byTruncatingTail
		textField.cell?.truncatesLastVisibleLine = true
		textField.translatesAutoresizingMaskIntoConstraints = false
		cell.addSubview(textField)
		cell.textField = textField
		NSLayoutConstraint.activate([
			textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
			textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
			textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
		])
		return cell
	}
}

enum Pasteboard {
	static func copy(_ string: String) {
		guard !string.isEmpty else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(string, forType: .string)
	}
}
