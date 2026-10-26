//
//  DownloadSheet.swift
//  Hackintool
//
//  Downloads a file to a chosen location while showing a progress sheet.
//

import Cocoa

final class DownloadSheet: NSObject, URLSessionDownloadDelegate {
	private let sheet: NSPanel
	private let messageLabel = NSTextField(labelWithString: "")
	private let detailLabel = NSTextField(labelWithString: "")
	private let progressBar = NSProgressIndicator()
	private var session: URLSession?
	private var destination: URL
	private var completion: ((URL?) -> Void)?
	/// Keeps the sheet alive while it's showing.
	private static var active: [DownloadSheet] = []

	/// Downloads `url` to `destination` with a sheet on `window`; `completion` gets the
	/// saved file, or nil if the download failed or was cancelled.
	static func download(_ url: URL, to destination: URL, title: String, on window: NSWindow, completion: @escaping (URL?) -> Void) {
		let download = DownloadSheet(destination: destination, completion: completion)
		active.append(download)
		download.messageLabel.stringValue = title
		window.beginSheet(download.sheet)
		let session = URLSession(configuration: .default, delegate: download, delegateQueue: .main)
		download.session = session
		session.downloadTask(with: url).resume()
	}

	private init(destination: URL, completion: @escaping (URL?) -> Void) {
		self.destination = destination
		self.completion = completion
		sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120), styleMask: [.titled], backing: .buffered, defer: true)
		super.init()

		messageLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
		detailLabel.textColor = .secondaryLabelColor
		progressBar.isIndeterminate = true
		progressBar.style = .bar
		progressBar.startAnimation(nil)
		let cancelButton = NSButton(title: L("Cancel"), target: self, action: #selector(cancel(_:)))
		cancelButton.keyEquivalent = "\u{1b}"

		let buttons = NSStackView(views: [NSView(), cancelButton])
		let stack = NSStackView(views: [messageLabel, progressBar, detailLabel, buttons])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 8
		stack.edgeInsets = NSEdgeInsets(all: 20)
		[progressBar, buttons].forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true }
		sheet.contentView = stack
	}

	@objc private func cancel(_ sender: Any?) {
		session?.invalidateAndCancel()
		finish(nil)
	}

	private func finish(_ url: URL?) {
		guard let completion = completion else { return }
		self.completion = nil
		sheet.sheetParent?.endSheet(sheet)
		session?.finishTasksAndInvalidate()
		DownloadSheet.active.removeAll { $0 === self }
		completion(url)
	}

	// MARK: URLSessionDownloadDelegate

	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		let megabytes = Double(totalBytesWritten) / (1024 * 1024)
		detailLabel.stringValue = L("%1.1f Mbytes", megabytes)
		guard totalBytesExpectedToWrite > 0 else { return }
		progressBar.isIndeterminate = false
		progressBar.maxValue = Double(totalBytesExpectedToWrite)
		progressBar.doubleValue = Double(totalBytesWritten)
	}

	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		do {
			if FileManager.default.fileExists(atPath: destination.path) {
				try FileManager.default.removeItem(at: destination)
			}
			try FileManager.default.moveItem(at: location, to: destination)
			finish(destination)
		} catch {
			Alerts.error("Download Failed", error.localizedDescription)
			finish(nil)
		}
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard let error = error, completion != nil else { return }
		if (error as NSError).code != NSURLErrorCancelled {
			Alerts.error("Download Failed", error.localizedDescription)
		}
		finish(nil)
	}
}
