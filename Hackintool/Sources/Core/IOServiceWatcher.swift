//
//  IOServiceWatcher.swift
//  Hackintool
//
//  Calls back on the main run loop when services of a class appear or disappear.
//

import Foundation
import IOKit

final class IOServiceWatcher {
	enum Event {
		case added(IORegistryEntry)
		case removed(IORegistryEntry)
	}

	private let handler: (Event) -> Void
	private var notificationPort: IONotificationPortRef?
	private var addedIterator: io_iterator_t = 0
	private var removedIterator: io_iterator_t = 0

	/// Starts watching. Services that already exist are not reported.
	init?(className: String, handler: @escaping (Event) -> Void) {
		self.handler = handler
		guard let port = IONotificationPortCreate(kIOMainPortDefaultCompat) else { return nil }
		notificationPort = port
		CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)

		let context = Unmanaged.passUnretained(self).toOpaque()
		let added: IOServiceMatchingCallback = { context, iterator in
			guard let context = context else { return }
			Unmanaged<IOServiceWatcher>.fromOpaque(context).takeUnretainedValue().drain(iterator, added: true)
		}
		let removed: IOServiceMatchingCallback = { context, iterator in
			guard let context = context else { return }
			Unmanaged<IOServiceWatcher>.fromOpaque(context).takeUnretainedValue().drain(iterator, added: false)
		}

		// Each call consumes a reference to its matching dictionary.
		guard IOServiceAddMatchingNotification(port, kIOPublishNotification, IOServiceMatching(className), added, context, &addedIterator) == KERN_SUCCESS,
		      IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching(className), removed, context, &removedIterator) == KERN_SUCCESS else {
			return nil
		}

		// Arm the notifications by draining the existing services without reporting them.
		_ = IORegistryEntry.collectWithoutReleasingIterator(addedIterator)
		_ = IORegistryEntry.collectWithoutReleasingIterator(removedIterator)
	}

	deinit {
		IOObjectRelease(addedIterator)
		IOObjectRelease(removedIterator)
		if let port = notificationPort {
			IONotificationPortDestroy(port)
		}
	}

	private func drain(_ iterator: io_iterator_t, added: Bool) {
		for entry in IORegistryEntry.collectWithoutReleasingIterator(iterator) {
			handler(added ? .added(entry) : .removed(entry))
		}
	}
}

extension IORegistryEntry {
	/// Like collect(_:), but leaves the iterator alive (notification iterators must stay armed).
	static func collectWithoutReleasingIterator(_ iterator: io_iterator_t) -> [IORegistryEntry] {
		var entries: [IORegistryEntry] = []
		while case let next = IOIteratorNext(iterator), next != 0 {
			if let entry = IORegistryEntry(owning: next) {
				entries.append(entry)
			}
		}
		return entries
	}
}

/// Coalesces bursts of hardware events (a hub with several devices, say) into one refresh.
final class Debouncer {
	private let delay: TimeInterval
	private var workItem: DispatchWorkItem?

	init(delay: TimeInterval) {
		self.delay = delay
	}

	func schedule(_ action: @escaping () -> Void) {
		workItem?.cancel()
		let item = DispatchWorkItem(block: action)
		workItem = item
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
	}
}
