//
//  ControlBar.swift
//  Hackintool
//
//  A row of controls above (or below) a page's main content, and helpers
//  for building the controls that go in it.
//

import Cocoa

enum ControlBar {
	/// A horizontal row of controls with standard margins: `views` on the left, `trailing` on the right.
	static func make(_ views: [NSView], trailing: [NSView] = []) -> NSView {
		let row = NSStackView()
		row.orientation = .horizontal
		row.alignment = .centerY
		row.spacing = 8
		row.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
		row.setViews(views, in: .leading)
		row.setViews(trailing, in: .trailing)
		// Hug the controls tightly so the row never grows taller than they are.
		row.setHuggingPriority(.required, for: .vertical)
		return row
	}

	/// Stacks an optional header and footer around content that fills the remaining height.
	static func stack(header: NSView?, content: NSView, footer: NSView? = nil) -> NSView {
		let container = NSView()
		var views: [NSView] = []
		if let header = header {
			views.append(header)
		}
		views.append(content)
		if let footer = footer {
			views.append(footer)
		}
		for view in views {
			view.translatesAutoresizingMaskIntoConstraints = false
			container.addSubview(view)
			NSLayoutConstraint.activate([
				view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
				view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			])
		}
		// Bars keep their natural height; the content takes the rest.
		for bar in [header, footer].compactMap({ $0 }) {
			bar.setContentHuggingPriority(.required, for: .vertical)
			bar.setContentCompressionResistancePriority(.required, for: .vertical)
		}
		content.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
		content.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
		NSLayoutConstraint.activate([
			views.first!.topAnchor.constraint(equalTo: container.topAnchor),
			views.last!.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])
		for (above, below) in zip(views, views.dropFirst()) {
			below.topAnchor.constraint(equalTo: above.bottomAnchor).isActive = true
		}
		return container
	}

	static func label(_ title: String) -> NSTextField {
		let label = NSTextField(labelWithString: L(title))
		label.textColor = .secondaryLabelColor
		return label
	}

	/// A push button with an optional icon and a localized title.
	static func button(_ title: String, symbol: Symbol? = nil, target: AnyObject?, action: Selector) -> NSButton {
		let button = NSButton(title: L(title), target: target, action: action)
		button.bezelStyle = .rounded
		if let symbol = symbol {
			button.image = symbol.image(description: L(title))
			button.imagePosition = .imageLeading
		}
		return button
	}

	/// A borderless icon-only button with a tooltip.
	static func iconButton(_ symbol: Symbol, toolTip: String, target: AnyObject?, action: Selector) -> NSButton {
		let button = NSButton(image: symbol.image(description: L(toolTip)), target: target, action: action)
		button.bezelStyle = .texturedRounded
		button.isBordered = true
		button.toolTip = L(toolTip)
		return button
	}

	static func popUp(_ titles: [String], target: AnyObject?, action: Selector) -> NSPopUpButton {
		let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
		popUp.addItems(withTitles: titles)
		popUp.target = target
		popUp.action = action
		return popUp
	}

	/// A heading for a group of controls or a table.
	static func heading(_ title: String) -> NSTextField {
		let label = NSTextField(labelWithString: L(title))
		label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
		return label
	}
}
