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

/// An icon followed by text.
enum ImageTextCell {
	static func make(in tableView: NSTableView, identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
		if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
			return cell
		}
		let cell = NSTableCellView()
		cell.identifier = identifier
		let imageView = NSImageView()
		imageView.setSymbolSize(16)
		let textField = NSTextField(labelWithString: "")
		textField.lineBreakMode = .byTruncatingTail
		textField.translatesAutoresizingMaskIntoConstraints = false
		cell.addSubview(imageView)
		cell.addSubview(textField)
		cell.imageView = imageView
		cell.textField = textField
		NSLayoutConstraint.activate([
			imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
			imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
			textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
			textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
		])
		return cell
	}
}

/// A thin capacity bar for showing how full something is.
enum UsageBar {
	static func make(fraction: Double?) -> NSView {
		let container = NSView()
		guard let fraction = fraction else { return container }
		let indicator = NSLevelIndicator()
		indicator.levelIndicatorStyle = .continuousCapacity
		indicator.minValue = 0
		indicator.maxValue = 1
		indicator.warningValue = 0.85
		indicator.criticalValue = 0.95
		indicator.doubleValue = fraction
		indicator.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(indicator)
		NSLayoutConstraint.activate([
			indicator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
			indicator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
			indicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
			indicator.heightAnchor.constraint(equalToConstant: 10),
		])
		return container
	}
}

enum Pasteboard {
	static func copy(_ string: String) {
		guard !string.isEmpty else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(string, forType: .string)
	}
}
