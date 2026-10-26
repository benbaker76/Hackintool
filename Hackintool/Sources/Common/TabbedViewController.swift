//
//  TabbedViewController.swift
//  Hackintool
//
//  A section with several pages, switched with a segmented control at the top.
//  Toolbar refresh and search are forwarded to the page that's showing.
//

import Cocoa

class TabbedViewController: NSViewController, SectionContent {
	struct Page {
		let title: String
		let viewController: NSViewController
	}

	private let pages: [Page]
	private let segmentedControl: NSSegmentedControl
	private let container = NSView()
	private let selectionKey: String

	/// - Parameter identifier: used to remember the selected page between launches.
	init(identifier: String, pages: [Page]) {
		self.pages = pages
		self.selectionKey = "SelectedPage." + identifier
		segmentedControl = NSSegmentedControl(labels: pages.map { $0.title }, trackingMode: .selectOne, target: nil, action: nil)
		super.init(nibName: nil, bundle: nil)
		segmentedControl.target = self
		segmentedControl.action = #selector(segmentChanged(_:))
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	override func loadView() {
		segmentedControl.segmentStyle = .automatic
		segmentedControl.translatesAutoresizingMaskIntoConstraints = false

		let header = NSView()
		header.addSubview(segmentedControl)
		NSLayoutConstraint.activate([
			segmentedControl.centerXAnchor.constraint(equalTo: header.centerXAnchor),
			segmentedControl.topAnchor.constraint(equalTo: header.topAnchor, constant: 10),
			segmentedControl.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -10),
		])

		view = NSView()
		header.translatesAutoresizingMaskIntoConstraints = false
		container.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(header)
		view.addSubview(container)
		NSLayoutConstraint.activate([
			header.topAnchor.constraint(equalTo: view.topAnchor),
			header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			container.topAnchor.constraint(equalTo: header.bottomAnchor),
			container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
		])
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		let saved = UserDefaults.standard.integer(forKey: selectionKey)
		select(pageAt: pages.indices.contains(saved) ? saved : 0)
	}

	var selectedPage: NSViewController? {
		let index = segmentedControl.selectedSegment
		return pages.indices.contains(index) ? pages[index].viewController : nil
	}

	func select(pageAt index: Int) {
		segmentedControl.selectedSegment = index
		children.forEach {
			$0.view.removeFromSuperview()
			$0.removeFromParent()
		}
		let page = pages[index].viewController
		addChild(page)
		container.addPinnedSubview(page.view)
		UserDefaults.standard.set(index, forKey: selectionKey)
		(view.window?.windowController as? MainWindowController)?.sectionContentDidChange()
	}

	@objc private func segmentChanged(_ sender: NSSegmentedControl) {
		select(pageAt: sender.selectedSegment)
	}

	// MARK: SectionContent

	private var selectedContent: SectionContent? {
		return selectedPage as? SectionContent
	}

	var canRefresh: Bool { return selectedContent?.canRefresh ?? false }
	func refresh() { selectedContent?.refresh() }
	var searchPlaceholder: String? { return selectedContent?.searchPlaceholder }
	func search(_ text: String) { selectedContent?.search(text) }

	/// Lets menu commands reach the selected page.
	override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
		if let page = selectedPage {
			if let target = page.supplementalTarget(forAction: action, sender: sender) {
				return target
			}
			if page.responds(to: action) {
				return page
			}
		}
		return super.supplementalTarget(forAction: action, sender: sender)
	}
}
