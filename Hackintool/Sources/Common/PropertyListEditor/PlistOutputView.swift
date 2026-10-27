//
//  PlistOutputView.swift
//  Hackintool
//
//  Generated output that's often a property list: shown as a Key / Type / Value tree
//  or as XML, switched with `modeControl`. Text that isn't a plist is always shown as text.
//

import Cocoa

final class PlistOutputView: NSView {
	enum Mode: Int {
		case tree, xml
	}

	let text = ScrollingTextView(monospaced: true, wraps: false)
	let editor = PropertyListEditor()
	/// Plist | XML, for the owner to put in its header or footer.
	let modeControl: NSSegmentedControl
	private var isPlist = false

	override init(frame frameRect: NSRect) {
		modeControl = NSSegmentedControl(labels: [L("Plist"), L("XML")], trackingMode: .selectOne, target: nil, action: nil)
		super.init(frame: frameRect)
		modeControl.target = self
		modeControl.action = #selector(modeChanged(_:))
		modeControl.setToolTip(L("Show the property list as a tree"), forSegment: 0)
		modeControl.setToolTip(L("Show the property list as XML"), forSegment: 1)
		editor.isEditable = false
		addPinnedSubview(text.scrollView)
		addPinnedSubview(editor)
		updateMode()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	/// The output text. XML plists also fill the tree, keeping their key order.
	var string: String {
		get { return text.string }
		set {
			text.string = newValue
			text.textView.scrollToBeginningOfDocument(nil)
			let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
			let node = trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<plist") ? PropertyListNode(xmlString: trimmed) : nil
			isPlist = node?.type.isContainer ?? false
			editor.setRootNode(isPlist ? node : nil)
			editor.expand(nil, expandChildren: true)
			updateMode()
		}
	}

	func clear() {
		string = ""
	}

	private var mode: Mode {
		return Mode(rawValue: Settings.plistOutputMode) ?? .tree
	}

	@objc private func modeChanged(_ sender: Any?) {
		Settings.plistOutputMode = modeControl.selectedSegment
		updateMode()
	}

	private func updateMode() {
		let showsTree = isPlist && mode == .tree
		editor.isHidden = !showsTree
		text.scrollView.isHidden = showsTree
		// Only plists have a tree to switch to; anything else is shown as text.
		modeControl.isEnabled = isPlist
		modeControl.selectedSegment = showsTree ? Mode.tree.rawValue : Mode.xml.rawValue
	}
}
