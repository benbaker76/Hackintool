//
//  StackedTablesViewController.swift
//  Hackintool
//
//  Several titled tables stacked vertically in resizable panes.
//  Search applies to every table; refresh calls the owner's handler.
//

import Cocoa

final class StackedTablesViewController: NSViewController, SectionContent {
	struct Pane {
		let title: String
		let viewController: NSViewController
	}

	private let panes: [Pane]
	private let splitView = NSSplitView()

	var onRefresh: (() -> Void)?

	init(panes: [Pane]) {
		self.panes = panes
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	override func loadView() {
		splitView.isVertical = false
		splitView.dividerStyle = .thin
		for pane in panes {
			addChild(pane.viewController)
			let heading = ControlBar.heading(pane.title)
			let header = NSStackView(views: [heading])
			header.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 4, right: 16)
			header.alignment = .centerY
			let paneView = ControlBar.stack(header: header, content: pane.viewController.view)
			paneView.heightAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
			splitView.addArrangedSubview(paneView)
		}

		// Equal heights to start with, at a priority low enough that dragging a divider wins.
		let paneViews = splitView.arrangedSubviews
		for paneView in paneViews.dropFirst() {
			let equal = paneView.heightAnchor.constraint(equalTo: paneViews[0].heightAnchor)
			equal.priority = .defaultLow
			equal.isActive = true
		}
		view = splitView
	}

	var canRefresh: Bool { return onRefresh != nil }
	func refresh() { onRefresh?() }
	var searchPlaceholder: String? { return L("Search") }

	func search(_ text: String) {
		panes.compactMap { $0.viewController as? SectionContent }.forEach { $0.search(text) }
	}
}
