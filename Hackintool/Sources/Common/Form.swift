//
//  Form.swift
//  Hackintool
//
//  Label / control forms laid out with NSGridView, optionally inside a titled box.
//

import Cocoa

enum Form {
	/// Rows of right-aligned labels and controls that fill the remaining width.
	static func grid(_ rows: [(label: String, control: NSView)]) -> NSView {
		let labels = rows.map { ControlBar.label($0.label) }
		let labelWidth = labels.map { $0.fittingSize.width }.max() ?? 0

		let rowViews = zip(labels, rows).map { label, row -> NSView in
			label.alignment = .right
			label.widthAnchor.constraint(equalToConstant: ceil(labelWidth)).isActive = true
			label.setContentHuggingPriority(.required, for: .horizontal)
			row.control.setContentHuggingPriority(.defaultLow, for: .horizontal)
			let rowStack = NSStackView(views: [label, row.control])
			rowStack.orientation = .horizontal
			rowStack.alignment = .firstBaseline
			rowStack.spacing = 12
			row.control.trailingAnchor.constraint(equalTo: rowStack.trailingAnchor).isActive = true
			return rowStack
		}

		let stack = NSStackView(views: rowViews)
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 8
		rowViews.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
		return stack
	}

	/// Wraps content in a titled box with standard padding.
	static func box(_ title: String, content: NSView) -> NSBox {
		let box = NSBox()
		box.title = L(title)
		box.titlePosition = .atTop
		box.contentViewMargins = NSSize(width: 12, height: 12)
		box.contentView?.addPinnedSubview(content, insets: NSEdgeInsets(all: 4))
		return box
	}

	/// An editable text field; monospaced suits hex and binary values.
	static func textField(monospaced: Bool = false, placeholder: String? = nil) -> NSTextField {
		let field = NSTextField(string: "")
		field.placeholderString = placeholder.map(L)
		field.lineBreakMode = .byTruncatingTail
		field.usesSingleLineMode = true
		if monospaced {
			field.font = .monospacedSystemFontCompat(ofSize: NSFont.systemFontSize)
		}
		field.setContentHuggingPriority(.defaultLow, for: .horizontal)
		return field
	}

	static func checkbox(_ title: String, identifier: String? = nil, target: AnyObject?, action: Selector) -> NSButton {
		let checkbox = NSButton(checkboxWithTitle: L(title), target: target, action: action)
		if let identifier = identifier {
			checkbox.identifier = NSUserInterfaceItemIdentifier(identifier)
			checkbox.toolTip = toolTip(identifier)
		}
		return checkbox
	}

	static func radio(_ title: String, target: AnyObject?, action: Selector) -> NSButton {
		return NSButton(radioButtonWithTitle: L(title), target: target, action: action)
	}

	/// A vertical stack of views with standard spacing and margins, scrollable if it overflows.
	static func scrollingStack(_ views: [NSView], spacing: CGFloat = 16, insets: NSEdgeInsets = NSEdgeInsets(all: 20)) -> NSScrollView {
		let stack = NSStackView(views: views)
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = spacing
		stack.edgeInsets = insets
		views.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(insets.left + insets.right)).isActive = true }

		let documentView = FlippedView()
		documentView.addPinnedSubview(stack)

		let scrollView = NSScrollView()
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = false
		scrollView.documentView = documentView
		documentView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
			documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
			documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
		])
		return scrollView
	}
}

/// A view with a top-left origin, so scroll view content starts at the top.
final class FlippedView: NSView {
	override var isFlipped: Bool { return true }
}

extension NSFont {
	/// Monospaced system font (SF Mono) on 10.15+, Menlo before that.
	static func monospacedSystemFontCompat(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
		if #available(macOS 10.15, *) {
			return .monospacedSystemFont(ofSize: size, weight: weight)
		}
		return NSFont(name: "Menlo", size: size) ?? .userFixedPitchFont(ofSize: size) ?? .systemFont(ofSize: size)
	}
}
