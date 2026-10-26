//
//  TextViews.swift
//  Hackintool
//
//  Scrolling text views for editors, logs and command output.
//

import Cocoa

final class ScrollingTextView {
	let scrollView: NSScrollView
	let textView: NSTextView

	/// - Parameters:
	///   - monospaced: use a fixed-width font (logs, hex, patches).
	///   - wraps: wrap long lines instead of scrolling horizontally.
	init(editable: Bool = false, monospaced: Bool = true, wraps: Bool = true) {
		scrollView = NSTextView.scrollableTextView()
		textView = scrollView.documentView as! NSTextView
		textView.isEditable = editable
		textView.isSelectable = true
		textView.isRichText = false
		textView.allowsUndo = editable
		textView.usesFindBar = true
		textView.isIncrementalSearchingEnabled = true
		textView.isAutomaticQuoteSubstitutionEnabled = false
		textView.isAutomaticDashSubstitutionEnabled = false
		textView.isAutomaticTextReplacementEnabled = false
		textView.isAutomaticSpellingCorrectionEnabled = false
		textView.textContainerInset = NSSize(width: 6, height: 6)
		textView.font = monospaced ? .monospacedSystemFontCompat(ofSize: NSFont.smallSystemFontSize + 1) : .systemFont(ofSize: NSFont.systemFontSize)
		scrollView.borderType = .noBorder

		if !wraps {
			scrollView.hasHorizontalScroller = true
			textView.isHorizontallyResizable = true
			textView.textContainer?.widthTracksTextView = false
			textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		}
	}

	var string: String {
		get { return textView.string }
		set { textView.string = newValue }
	}

	/// Appends text, optionally coloured, and scrolls to the end.
	func append(_ text: String, color: NSColor = .labelColor, background: NSColor? = nil) {
		var attributes: [NSAttributedString.Key: Any] = [
			.foregroundColor: color,
			.font: textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
		]
		attributes[.backgroundColor] = background
		textView.textStorage?.append(NSAttributedString(string: text, attributes: attributes))
		textView.scrollToEndOfDocument(nil)
	}

	func clear() {
		textView.string = ""
	}
}
