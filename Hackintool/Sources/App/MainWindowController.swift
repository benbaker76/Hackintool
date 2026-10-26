//
//  MainWindowController.swift
//  Hackintool
//
//  The single main window: a sidebar of sections and the selected section's content.
//

import Cocoa

final class MainWindowController: NSWindowController {
	private let splitViewController = NSSplitViewController()
	private let sidebarViewController = SidebarViewController()
	private let containerViewController = ContentContainerViewController()

	private var sectionViewControllers: [Section: NSViewController] = [:]
	private weak var searchField: NSSearchField?
	private weak var refreshItem: NSToolbarItem?

	private static let selectedSectionKey = "SelectedSection"

	init() {
		var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
		if #available(macOS 11.0, *) {
			// Lets the sidebar run the full height of the window, under the toolbar.
			styleMask.insert(.fullSizeContentView)
		}
		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
		                      styleMask: styleMask, backing: .buffered, defer: false)
		window.title = "Hackintool"
		window.minSize = NSSize(width: 820, height: 520)
		window.setFrameAutosaveName("MainWindow")
		super.init(window: window)

		let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
		sidebarItem.minimumThickness = 180
		sidebarItem.maximumThickness = 280
		sidebarItem.canCollapse = true
		splitViewController.addSplitViewItem(sidebarItem)

		let contentItem = NSSplitViewItem(viewController: containerViewController)
		contentItem.minimumThickness = 600
		splitViewController.addSplitViewItem(contentItem)
		splitViewController.splitView.autosaveName = "MainSplitView"

		sidebarViewController.delegate = self
		window.contentViewController = splitViewController
		window.setContentSize(NSSize(width: 1100, height: 720))
		configureToolbar()

		let savedSection = UserDefaults.standard.string(forKey: Self.selectedSectionKey).flatMap(Section.init(rawValue:))
		show(savedSection ?? .system)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	var currentSection: Section? {
		return sidebarViewController.selectedSection
	}

	func show(_ section: Section) {
		sidebarViewController.select(section)
		if sidebarViewController.selectedSection == section {
			display(section)
		}
	}

	private func display(_ section: Section) {
		let viewController = sectionViewControllers[section] ?? section.makeViewController()
		sectionViewControllers[section] = viewController
		containerViewController.show(viewController)

		UserDefaults.standard.set(section.rawValue, forKey: Self.selectedSectionKey)
		if #available(macOS 11.0, *) {
			window?.subtitle = section.title
		} else {
			window?.title = "Hackintool – " + section.title
		}
		updateToolbar(for: viewController as? SectionContent)
	}

	/// Call when a section switches pages, so the toolbar reflects the new page.
	func sectionContentDidChange() {
		updateToolbar(for: currentContent)
	}

	private var currentContent: SectionContent? {
		return currentSection.flatMap { sectionViewControllers[$0] } as? SectionContent
	}

	@objc func refresh(_ sender: Any?) {
		currentContent?.refresh()
	}

	@objc func search(_ sender: NSSearchField) {
		currentContent?.search(sender.stringValue)
	}

	/// View ▸ <section>; the menu item's represented object is the section's raw value.
	@objc func showSection(_ sender: NSMenuItem) {
		guard let section = (sender.representedObject as? String).flatMap(Section.init(rawValue:)) else { return }
		show(section)
	}

	/// Sends menu commands the window doesn't handle to the section that's showing,
	/// even when keyboard focus is in the sidebar.
	override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
		if let viewController = currentSection.flatMap({ sectionViewControllers[$0] }) {
			if let target = viewController.supplementalTarget(forAction: action, sender: sender) ?? (viewController.responds(to: action) ? viewController : nil) {
				return target
			}
		}
		return super.supplementalTarget(forAction: action, sender: sender)
	}

	/// Moves keyboard focus to the toolbar search field (Edit ▸ Find).
	@objc func focusSearch(_ sender: Any?) {
		guard let searchField = searchField, searchField.isEnabled else { return }
		window?.makeFirstResponder(searchField)
	}

	private func updateToolbar(for content: SectionContent?) {
		refreshItem?.isEnabled = content?.canRefresh ?? false
		guard let searchField = searchField else { return }
		searchField.stringValue = ""
		searchField.isEnabled = content?.searchPlaceholder != nil
		searchField.placeholderString = content?.searchPlaceholder ?? L("Search")
	}
}

extension MainWindowController: NSMenuItemValidation {
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(showSection(_:)):
			menuItem.state = (menuItem.representedObject as? String) == currentSection?.rawValue ? .on : .off
			return true
		case #selector(refresh(_:)):
			return currentContent?.canRefresh ?? false
		case #selector(focusSearch(_:)):
			return currentContent?.searchPlaceholder != nil
		default:
			return true
		}
	}
}

extension MainWindowController: SidebarViewControllerDelegate {
	func sidebar(_ sidebar: SidebarViewController, didSelect section: Section) {
		display(section)
	}
}

// MARK: - Toolbar

private extension NSToolbarItem.Identifier {
	static let refresh = NSToolbarItem.Identifier("Refresh")
	static let search = NSToolbarItem.Identifier("Search")
}

extension MainWindowController: NSToolbarDelegate {
	private func configureToolbar() {
		let toolbar = NSToolbar(identifier: "MainToolbar")
		toolbar.delegate = self
		toolbar.displayMode = .iconOnly
		toolbar.allowsUserCustomization = false
		window?.toolbar = toolbar
		if #available(macOS 11.0, *) {
			window?.toolbarStyle = .unified
		} else {
			window?.titleVisibility = .visible
		}
	}

	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		var identifiers: [NSToolbarItem.Identifier] = [.toggleSidebar]
		if #available(macOS 11.0, *) {
			identifiers.append(.sidebarTrackingSeparator)
		}
		identifiers += [.flexibleSpace, .refresh, .search]
		return identifiers
	}

	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		return toolbarDefaultItemIdentifiers(toolbar)
	}

	func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
		switch itemIdentifier {
		case .refresh:
			let item = NSToolbarItem(itemIdentifier: itemIdentifier)
			item.label = L("Refresh")
			item.toolTip = L("Refresh")
			item.image = Symbol.refresh.image(description: L("Refresh"))
			item.target = self
			item.action = #selector(refresh(_:))
			if #available(macOS 10.15, *) {
				item.isBordered = true
			}
			refreshItem = item
			return item

		case .search:
			let item: NSToolbarItem
			let searchField: NSSearchField
			if #available(macOS 11.0, *) {
				let searchItem = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
				searchField = searchItem.searchField
				item = searchItem
			} else {
				searchField = NSSearchField()
				searchField.widthAnchor.constraint(equalToConstant: 220).isActive = true
				item = NSToolbarItem(itemIdentifier: itemIdentifier)
				item.view = searchField
			}
			item.label = L("Search")
			searchField.sendsSearchStringImmediately = false
			searchField.sendsWholeSearchString = false
			searchField.target = self
			searchField.action = #selector(search(_:))
			self.searchField = searchField
			return item

		default:
			return nil
		}
	}
}

/// Hosts the current section's view controller.
final class ContentContainerViewController: NSViewController {
	override func loadView() {
		view = NSView()
	}

	func show(_ viewController: NSViewController) {
		children.forEach {
			$0.view.removeFromSuperview()
			$0.removeFromParent()
		}
		addChild(viewController)

		// Keep content clear of the toolbar when the window uses a full-size content view.
		let child = viewController.view
		child.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(child)
		let topAnchor: NSLayoutYAxisAnchor
		if #available(macOS 11.0, *) {
			topAnchor = view.safeAreaLayoutGuide.topAnchor
		} else {
			topAnchor = view.topAnchor
		}
		NSLayoutConstraint.activate([
			child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			child.topAnchor.constraint(equalTo: topAnchor),
			child.bottomAnchor.constraint(equalTo: view.bottomAnchor),
		])
	}
}
