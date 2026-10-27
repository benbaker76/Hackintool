//
//  StatusViews.swift
//  Hackintool
//
//  Small status visuals: a coloured badge for table cells, and the message shown
//  in place of an empty table.
//

import Cocoa

/// A rounded, tinted label such as "Update" or "Enabled", for status columns.
enum StatusBadge {
	static func make(_ title: String, color: NSColor, symbol: Symbol? = nil) -> NSView {
		let container = NSView()
		guard !title.isEmpty else { return container }
		let badge = BadgeView(color: color)
		let label = NSTextField(labelWithString: title)
		label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
		label.textColor = color
		label.lineBreakMode = .byTruncatingTail
		var views: [NSView] = [label]
		if let symbol = symbol {
			let imageView = NSImageView(image: symbol.image(size: 12))
			imageView.contentTintColor = color
			views.insert(imageView, at: 0)
		}
		let stack = NSStackView(views: views)
		stack.spacing = 3
		stack.edgeInsets = NSEdgeInsets(top: 1, left: 7, bottom: 1, right: 8)
		badge.addPinnedSubview(stack)
		badge.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(badge)
		NSLayoutConstraint.activate([
			badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
			badge.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -2),
			badge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
			badge.heightAnchor.constraint(equalToConstant: 18),
		])
		container.toolTip = title
		return container
	}

	private final class BadgeView: NSView {
		private let color: NSColor

		init(color: NSColor) {
			self.color = color
			super.init(frame: .zero)
		}

		required init?(coder: NSCoder) {
			fatalError("init(coder:) is not supported")
		}

		override func draw(_ dirtyRect: NSRect) {
			color.withAlphaComponent(0.15).setFill()
			NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
		}
	}
}

/// What an empty table says, e.g. "No Audio Devices" with a hint underneath.
struct EmptyState {
	let symbol: Symbol
	let title: String
	let message: String?

	/// - Parameters: English text, localized for display.
	init(_ symbol: Symbol, _ title: String, _ message: String? = nil) {
		self.symbol = symbol
		self.title = L(title)
		self.message = message.map(L)
	}
}

/// A centred icon, title and hint, laid over an empty table.
final class EmptyStateView: NSView {
	private let imageView = NSImageView()
	private let titleLabel = NSTextField(labelWithString: "")
	private let messageLabel = NSTextField(wrappingLabelWithString: "")

	init() {
		super.init(frame: .zero)
		imageView.contentTintColor = .tertiaryLabelColor
		titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
		titleLabel.textColor = .secondaryLabelColor
		titleLabel.alignment = .center
		messageLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
		messageLabel.textColor = .secondaryLabelColor
		messageLabel.alignment = .center
		messageLabel.preferredMaxLayoutWidth = 360

		let stack = NSStackView(views: [imageView, titleLabel, messageLabel])
		stack.orientation = .vertical
		stack.alignment = .centerX
		stack.spacing = 6
		stack.setCustomSpacing(10, after: imageView)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
			stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
			stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
			messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	func show(_ state: EmptyState) {
		imageView.image = state.symbol.image(size: 40)
		titleLabel.stringValue = state.title
		messageLabel.stringValue = state.message ?? ""
		messageLabel.isHidden = state.message == nil
		// Short panes only have room for the title.
		imageView.isHidden = bounds.height > 0 && bounds.height < 140
	}

	override func layout() {
		super.layout()
		imageView.isHidden = bounds.height < 140
	}

	/// Clicks go through to the table underneath.
	override func hitTest(_ point: NSPoint) -> NSView? {
		return nil
	}
}
