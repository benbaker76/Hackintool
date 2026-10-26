//
//  IDDatabase.swift
//  Hackintool
//
//  Vendor, device and class names from the pci.ids and usb.ids databases.
//  A copy ships in the bundle; an updated copy can be downloaded into Caches.
//

import Foundation

final class IDDatabase {
	struct Vendor {
		let name: String
		var devices: [UInt32: String] = [:]
		/// Keyed by (subsystem vendor << 16) | subsystem device.
		var subsystems: [UInt32: String] = [:]
	}

	struct DeviceClass {
		let name: String
		var subclasses: [UInt32: String] = [:]
		var programmingInterfaces: [UInt32: String] = [:]
	}

	static let pci = IDDatabase(fileName: "pci.ids", bundleDirectory: "PCI", downloadURL: URL(string: "https://pci-ids.ucw.cz/pci.ids")!)
	static let usb = IDDatabase(fileName: "usb.ids", bundleDirectory: "USB", downloadURL: URL(string: "http://www.linux-usb.org/usb.ids")!)

	let fileName: String
	let downloadURL: URL
	private let bundleURL: URL?

	private(set) var vendors: [UInt32: Vendor] = [:]
	private(set) var classes: [UInt32: DeviceClass] = [:]
	private var isLoaded = false
	private let lock = NSLock()

	private init(fileName: String, bundleDirectory: String, downloadURL: URL) {
		self.fileName = fileName
		self.downloadURL = downloadURL
		let name = (fileName as NSString).deletingPathExtension
		let ext = (fileName as NSString).pathExtension
		bundleURL = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: bundleDirectory)
	}

	var cacheURL: URL? {
		return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
	}

	/// The newer of the downloaded and bundled copies.
	private var sourceURL: URL? {
		func modified(_ url: URL?) -> Date? {
			guard let url = url else { return nil }
			return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
		}
		if let cacheDate = modified(cacheURL), cacheDate >= (modified(bundleURL) ?? .distantPast) {
			return cacheURL
		}
		return bundleURL
	}

	// MARK: Lookup

	func vendorName(_ vendorID: UInt32) -> String? {
		loadIfNeeded()
		return vendors[vendorID]?.name
	}

	func deviceName(vendorID: UInt32, deviceID: UInt32) -> String? {
		loadIfNeeded()
		return vendors[vendorID]?.devices[deviceID]
	}

	/// PCI class codes are 0xCCSSPP (class, subclass, programming interface).
	func className(classCode: UInt32) -> (className: String?, subclassName: String?) {
		loadIfNeeded()
		let deviceClass = classes[(classCode >> 16) & 0xFF]
		return (deviceClass?.name, deviceClass?.subclasses[(classCode >> 8) & 0xFF])
	}

	// MARK: Loading

	func loadIfNeeded() {
		lock.lock()
		defer { lock.unlock() }
		guard !isLoaded else { return }
		isLoaded = true
		if let url = sourceURL, let text = try? String(contentsOf: url, encoding: .isoLatin1) {
			parse(text)
		}
	}

	/// Downloads the latest database into Caches and reloads it.
	func update(completion: @escaping (Bool) -> Void) {
		let task = URLSession.shared.dataTask(with: downloadURL) { [weak self] data, response, _ in
			guard let self = self, let data = data, let cacheURL = self.cacheURL,
			      (response as? HTTPURLResponse)?.statusCode == 200,
			      (try? data.write(to: cacheURL, options: .atomic)) != nil else {
				DispatchQueue.main.async { completion(false) }
				return
			}
			self.lock.lock()
			self.isLoaded = false
			self.vendors = [:]
			self.classes = [:]
			self.lock.unlock()
			self.loadIfNeeded()
			DispatchQueue.main.async { completion(true) }
		}
		task.resume()
	}

	/// Format (https://pci-ids.ucw.cz/):
	///   vendor  vendor_name
	///   \tdevice  device_name
	///   \t\tsubvendor subdevice  subsystem_name
	///   C class  class_name
	///   \tsubclass  subclass_name
	///   \t\tprog-if  prog-if_name
	private func parse(_ text: String) {
		var currentVendor: UInt32?
		var currentClass: UInt32?
		var readingClasses = false

		for line in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r" }) {
			if line.hasPrefix("# List of known device") {
				readingClasses = true
				continue
			}
			if line.hasPrefix("#") {
				continue
			}

			let depth = line.prefix { $0 == "\t" }.count
			let body = line.dropFirst(depth)
			guard let separator = body.range(of: "  ") else { continue }
			let idPart = body[body.startIndex..<separator.lowerBound]
			let name = String(body[separator.upperBound...])

			if readingClasses {
				switch depth {
				case 0 where idPart.hasPrefix("C "):
					guard let id = UInt32(idPart.dropFirst(2), radix: 16) else { continue }
					classes[id] = DeviceClass(name: name)
					currentClass = id
				case 1:
					guard let classID = currentClass, let id = UInt32(idPart, radix: 16) else { continue }
					classes[classID]?.subclasses[id] = name
				case 2:
					guard let classID = currentClass, let id = UInt32(idPart, radix: 16) else { continue }
					classes[classID]?.programmingInterfaces[id] = name
				default:
					continue
				}
			} else {
				switch depth {
				case 0:
					guard let id = UInt32(idPart, radix: 16) else {
						// Other top-level lists in usb.ids (HID usages, languages...) follow the vendors.
						currentVendor = nil
						continue
					}
					vendors[id] = Vendor(name: name)
					currentVendor = id
				case 1:
					guard let vendorID = currentVendor, let id = UInt32(idPart, radix: 16) else { continue }
					vendors[vendorID]?.devices[id] = name
				case 2:
					let ids = idPart.split(separator: " ").compactMap { UInt32($0, radix: 16) }
					guard let vendorID = currentVendor, ids.count == 2 else { continue }
					vendors[vendorID]?.subsystems[ids[0] << 16 | ids[1]] = name
				default:
					continue
				}
			}
		}
	}
}
