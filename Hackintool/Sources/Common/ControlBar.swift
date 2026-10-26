//
//  ControlBar.swift
//  Hackintool
//
//  A row of controls above (or below) a page's main content, and helpers
//  for building the controls that go in it.
//

import Cocoa

enum ControlBar {
	/// A horizontal row of controls with standard margins.
	static func make(_ views: [NSView], trailing: [NSView] = []) -> NSView {
		let leading = NSStackView(views: views)
		leading.orientation = .horizontal
		leading.spacing = 8
		leading.alignment = .centerY

		let trailingStack = NSStackView(views: trailing)
		trailingStack.orientation = .horizontal
		trailingStack.spacing = 8
		trailingStack.alignment = .centerY

		let row = NSStackView(views: [leading, NSView(), trailingStack])
		row.orientation = .horizontal
		row.alignment = .centerY
		row.distribution = .fill
		row.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
		row.setHuggingPriority(.required, for: .vertical)
		return row
	}

	/// Stacks a control bar above content and returns the combined view.
	static func stack(header: NSView?, content: NSView, footer: NSView? = nil) -> NSView {
		var views: [NSView] = []
		if let header = header {
			views.append(header)
		}
		views.append(content)
		if let footer = footer {
			views.append(footer)
		}
		let stack = NSStackView(views: views)
		stack.orientation = .vertical
		stack.spacing = 0
		stack.alignment = .leading
		views.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
		content.setContentHuggingPriority(.defaultLow, for: .vertical)
		content.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

		let container = NSView()
		container.addPinnedSubview(stack)
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
