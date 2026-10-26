//
//  SidebarViewController.swift
//  Hackintool
//
//  Source-list sidebar with one row per section, grouped under headers.
//

import Cocoa

protocol SidebarViewControllerDelegate: AnyObject {
	func sidebar(_ sidebar: SidebarViewController, didSelect section: Section)
}

final class SidebarViewController: NSViewController {
	weak var delegate: SidebarViewControllerDelegate?

	/// NSOutlineView tracks items by object identity, so each row needs one stable object.
	private final class Node: NSObject {
		let group: Section.Group?
		let section: Section?
		let children: [Node]

		init(group: Section.Group) {
			self.group = group
			self.section = nil
			self.children = group.sections.map(Node.init(section:))
		}

		init(section: Section) {
			self.group = nil
			self.section = section
			self.children = []
		}
	}

	private let outlineView = NSOutlineView()
	private let groups = Section.Group.allCases.map(Node.init(group:))

	private static let sectionCellID = NSUserInterfaceItemIdentifier("SectionCell")
	private static let headerCellID = NSUserInterfaceItemIdentifier("HeaderCell")

	private(set) var selectedSection: Section?

	override func loadView() {
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Section"))
		column.resizingMask = .autoresizingMask
		outlineView.addTableColumn(column)
		outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
		outlineView.outlineTableColumn = column
		outlineView.headerView = nil
		outlineView.floatsGroupRows = false
		outlineView.rowSizeStyle = .default
		outlineView.indentationPerLevel = 0
		outlineView.dataSource = self
		outlineView.delegate = self
		if #available(macOS 11.0, *) {
			outlineView.style = .sourceList
		} else {
			outlineView.selectionHighlightStyle = .sourceList
		}

		let scrollView = NSScrollView()
		scrollView.documentView = outlineView
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = false
		scrollView.autohidesScrollers = true

		view = NSView()
		view.addPinnedSubview(scrollView)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		outlineView.reloadData()
		groups.forEach { outlineView.expandItem($0) }
	}

	func select(_ section: Section) {
		guard let node = groups.lazy.flatMap({ $0.children }).first(where: { $0.section == section }) else { return }
		let row = outlineView.row(forItem: node)
		guard row >= 0 else { return }
		outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		outlineView.scrollRowToVisible(row)
	}
}

extension SidebarViewController: NSOutlineViewDataSource {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		guard let node = item as? Node else { return groups.count }
		return node.children.count
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		guard let node = item as? Node else { return groups[index] }
		return node.children[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		return (item as? Node)?.group != nil
	}
}

extension SidebarViewController: NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
		return (item as? Node)?.group != nil
	}

	func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
		return (item as? Node)?.section != nil
	}

	func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
		return false
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? Node else { return nil }
		if let group = node.group {
			let cell = outlineView.makeView(withIdentifier: Self.headerCellID, owner: self) as? NSTableCellView ?? makeHeaderCell()
			cell.textField?.stringValue = group.title
			return cell
		}

		guard let section = node.section else { return nil }
		let cell = outlineView.makeView(withIdentifier: Self.sectionCellID, owner: self) as? NSTableCellView ?? makeSectionCell()
		cell.textField?.stringValue = section.title
		cell.imageView?.image = section.symbol.image(description: section.title, size: 18)
		return cell
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		guard let section = (outlineView.item(atRow: outlineView.selectedRow) as? Node)?.section, section != selectedSection else { return }
		selectedSection = section
		delegate?.sidebar(self, didSelect: section)
	}

	private func makeHeaderCell() -> NSTableCellView {
		let cell = NSTableCellView()
		cell.identifier = Self.headerCellID
		let textField = NSTextField(labelWithString: "")
		cell.textField = textField
		cell.addSubview(textField)
		textField.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
			textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
			textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
		])
		return cell
	}

	private func makeSectionCell() -> NSTableCellView {
		let cell = NSTableCellView()
		cell.identifier = Self.sectionCellID

		let imageView = NSImageView()
		imageView.setSymbolSize(18)
		imageView.setTint(.controlAccentColorCompat)
		cell.imageView = imageView

		let textField = NSTextField(labelWithString: "")
		textField.lineBreakMode = .byTruncatingTail
		cell.textField = textField

		cell.addSubview(imageView)
		cell.addSubview(textField)
		textField.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
			imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
			textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
			textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
		])
		return cell
	}
}

extension NSColor {
	/// The user's accent colour, or the system blue before macOS 10.14.
	static var controlAccentColorCompat: NSColor {
		if #available(macOS 10.14, *) {
			return .controlAccentColor
		}
		return .systemBlue
	}
}
