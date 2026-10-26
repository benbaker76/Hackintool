//
//  AppKit+Helpers.swift
//  Hackintool
//
//  Small AppKit conveniences. Anything newer than macOS 10.13 is wrapped
//  in an availability check so the deployment target can be lowered later.
//

import Cocoa

extension NSImageView {
	/// Pins the image view to a square of the given size and scales the image to fit.
	func setSymbolSize(_ size: CGFloat) {
		imageScaling = .scaleProportionallyUpOrDown
		translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: size),
			heightAnchor.constraint(equalToConstant: size),
		])
	}

	/// Tints a template image. Before macOS 10.14 template images keep the default label colour.
	func setTint(_ color: NSColor) {
		if #available(macOS 10.14, *) {
			contentTintColor = color
		}
	}
}

extension NSView {
	/// Adds a subview pinned to all four edges, with optional insets.
	func addPinnedSubview(_ subview: NSView, insets: NSEdgeInsets = NSEdgeInsets()) {
		subview.translatesAutoresizingMaskIntoConstraints = false
		addSubview(subview)
		NSLayoutConstraint.activate([
			subview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
			subview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
			subview.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
			subview.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
		])
	}
}

extension NSEdgeInsets {
	init(all inset: CGFloat) {
		self.init(top: inset, left: inset, bottom: inset, right: inset)
	}
}

extension Comparable {
	func clamped(to range: ClosedRange<Self>) -> Self {
		return min(max(self, range.lowerBound), range.upperBound)
	}
}
