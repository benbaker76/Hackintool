//
//  PlaceholderViewController.swift
//  Hackintool
//
//  Shown for sections that haven't been ported to Swift yet.
//

import Cocoa

final class PlaceholderViewController: NSViewController {
	private let section: Section

	init(section: Section) {
		self.section = section
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	override func loadView() {
		let imageView = NSImageView(image: section.symbol.image(size: 48))
		imageView.setTint(.tertiaryLabelColor)
		imageView.setSymbolSize(48)

		let titleLabel = NSTextField(labelWithString: section.title)
		titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 4, weight: .semibold)
		titleLabel.textColor = .secondaryLabelColor

		let stack = NSStackView(views: [imageView, titleLabel])
		stack.orientation = .vertical
		stack.spacing = 12

		view = NSView()
		view.addSubview(stack)
		stack.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
		])
	}
}
