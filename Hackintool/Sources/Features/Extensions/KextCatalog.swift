//
//  KextCatalog.swift
//  Hackintool
//
//  The bundled list of well-known Hackintosh kexts (Resources/Kexts/kexts.plist),
//  their loaded versions, and the latest source and release versions online.
//

import Foundation

final class KextEntry {
	let name: String
	let bundleID: String?
	let description: String
	let projectURL: String
	/// An explicit .xcodeproj URL when the project isn't at <repo>/<Name>.xcodeproj.
	let projectFileURL: String?
	let scheme: String?
	/// A shell snippet to run after cloning; $(OUTPUT_PATH) is the clone.
	let preBuildBash: String?
	/// "Lilu" for Lilu plugins.
	let type: String?
	/// The kext that replaces this one, if it's obsolete.
	let superseder: String?

	var installedVersion: String?
	/// CURRENT_PROJECT_VERSION / MODULE_VERSION from the project on GitHub.
	var currentVersion: String?
	var downloadVersion: String?
	var downloadURL: URL?

	init(dictionary: [String: Any]) {
		name = dictionary["Name"] as? String ?? "?"
		bundleID = dictionary["BundleID"] as? String
		description = dictionary["Description"] as? String ?? ""
		projectURL = dictionary["ProjectUrl"] as? String ?? ""
		projectFileURL = dictionary["ProjectFileUrl"] as? String
		scheme = dictionary["Scheme"] as? String
		preBuildBash = dictionary["PreBuildBash"] as? String
		type = dictionary["Type"] as? String
		superseder = (dictionary["Superseder"] as? String).flatMap { $0.isEmpty ? nil : $0 }
		downloadURL = (dictionary["DownloadUrl"] as? String).flatMap(URL.init(string:))
	}

	var isLilu: Bool { return name == "Lilu" }
	var isLiluPlugin: Bool { return type == "Lilu" }
	var isAcidanthera: Bool { return projectURL.contains("acidanthera") }
	var repository: (owner: String, repository: String)? { return GitHub.repository(from: projectURL) }

	var projectFileName: String {
		if let url = projectFileURL.flatMap(URL.init(string:)) {
			return url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
		}
		return name + ".xcodeproj"
	}
}

enum KextCatalog {
	static func load() -> [KextEntry] {
		guard let url = Bundle.main.url(forResource: "kexts", withExtension: "plist", subdirectory: "Kexts"),
		      let array = NSArray(contentsOf: url) as? [[String: Any]] else { return [] }
		let loaded = loadedKextVersions()
		return array.map(KextEntry.init(dictionary:))
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
			.map { entry in
				entry.installedVersion = loaded[(entry.bundleID ?? entry.name).lowercased()]
				#if DEBUG
				if SampleData.isEnabled, entry.installedVersion != nil {
					entry.downloadVersion = SampleData.latestKextVersions[entry.name.lowercased()] ?? entry.installedVersion
				}
				#endif
				return entry
			}
	}

	/// Loaded kext versions keyed by the last component of the bundle ID, lowercased
	/// ("as.vit9696.lilu" → "lilu"), as the original app matched them.
	static func loadedKextVersions() -> [String: String] {
		#if DEBUG
		if SampleData.isEnabled { return SampleData.loadedKextVersions }
		#endif
		var versions: [String: String] = [:]
		// kmutil replaced kextstat on macOS 11; kextstat still works but warns.
		guard let output = Shell.output("/usr/sbin/kextstat", ["-l"]) else { return versions }
		for line in output.split(separator: "\n") {
			let fields = line.split(separator: " ", omittingEmptySubsequences: true)
			guard fields.count >= 7 else { continue }
			let bundleID = fields[5].split(separator: ".").filter { $0 != "kext" }
			guard let name = bundleID.last else { continue }
			let version = fields[6].trimmingCharacters(in: CharacterSet(charactersIn: "()"))
			versions[name.lowercased()] = version
		}
		return versions
	}

	/// Fills in the latest release and project versions for each entry; `progress` runs on the main queue.
	static func checkVersions(_ entries: [KextEntry], progress: @escaping (Int) -> Void, completion: @escaping () -> Void) {
		DispatchQueue.global(qos: .userInitiated).async {
			for (index, entry) in entries.enumerated() {
				if let repository = entry.repository {
					let semaphore = DispatchSemaphore(value: 0)
					// Called back off the main queue so this loop can wait for it.
					GitHub.latestRelease(owner: repository.owner, repository: repository.repository, queue: nil) { release in
						// acidanthera publishes -DEBUG.zip before -RELEASE.zip; take the release build.
						let zips = release?.assets.filter { $0.name.lowercased().hasSuffix(".zip") } ?? []
						let preferred = zips.first { $0.name.uppercased().contains("RELEASE") }
							?? zips.first { !$0.name.uppercased().contains("DEBUG") }
							?? zips.first
						if let asset = preferred ?? release?.assets.first {
							entry.downloadURL = asset.downloadURL
							entry.downloadVersion = release?.version
						}
						semaphore.signal()
					}
					semaphore.wait()
				}
				entry.currentVersion = projectVersion(for: entry)
				DispatchQueue.main.async { progress(index) }
			}
			DispatchQueue.main.async(execute: completion)
		}
	}

	/// Reads the version from the project's project.pbxproj on GitHub (or SourceForge).
	private static func projectVersion(for entry: KextEntry) -> String? {
		var candidates: [URL] = []
		if let projectFileURL = entry.projectFileURL.flatMap(URL.init(string:)) {
			candidates.append(projectFileURL.appendingPathComponent("project.pbxproj"))
		} else if let (owner, repository) = entry.repository {
			let base = "https://raw.githubusercontent.com/\(owner)/\(repository)/HEAD/"
			candidates += [
				URL(string: base + "\(entry.name).xcodeproj/project.pbxproj"),
				URL(string: base + "\(entry.name)/\(entry.name).xcodeproj/project.pbxproj"),
			].compactMap { $0 }
		} else if entry.projectURL.contains("sourceforge.net") {
			candidates += [URL(string: "\(entry.projectURL)/code/HEAD/tree/\(entry.name)/\(entry.name).xcodeproj/project.pbxproj?format=raw")].compactMap { $0 }
		}
		for url in candidates {
			if let data = try? Data(contentsOf: url), let version = version(fromProjectFile: data) {
				return version
			}
		}
		return nil
	}

	static func version(fromProjectFile data: Data) -> String? {
		guard let project = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
		      let objects = project["objects"] as? [String: [String: Any]] else { return nil }
		let placeholders: Set<String> = ["$(MODULE_VERSION)", "$MODULE_VERSION", "$(CURRENT_PROJECT_VERSION)", "$CURRENT_PROJECT_VERSION"]
		for object in objects.values {
			guard let settings = object["buildSettings"] as? [String: Any] else { continue }
			for key in ["CURRENT_PROJECT_VERSION", "MODULE_VERSION"] {
				if let version = settings[key] as? String, !placeholders.contains(version) {
					return version
				}
			}
		}
		return nil
	}
}

/// Downloading release zips and building kexts from source, reporting output as it goes.
final class KextJobs {
	typealias Output = (_ text: String, _ isError: Bool) -> Void

	private let output: Output
	private let progress: (Double) -> Void

	init(output: @escaping Output, progress: @escaping (Double) -> Void) {
		self.output = output
		self.progress = progress
	}

	private func log(_ text: String) {
		DispatchQueue.main.async { self.output(text, false) }
	}

	@discardableResult
	private func run(_ launchPath: String, _ arguments: [String], in directory: String = "/") -> Int32 {
		log("$ \((launchPath as NSString).lastPathComponent) \(arguments.joined(separator: " "))\n")
		return Shell.runStreaming(launchPath, arguments, currentDirectory: directory, output: output)
	}

	/// Downloads each entry's release zip and unzips it into Desktop/Hackintool_Kexts.
	func download(_ entries: [KextEntry], completion: @escaping (URL) -> Void) {
		let destination = KextJobs.desktop.appendingPathComponent("Hackintool_Kexts")
		DispatchQueue.global(qos: .userInitiated).async {
			try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
			for (index, entry) in entries.enumerated() {
				guard let url = entry.downloadURL else {
					self.log(L("No download available for %@. Check versions first.", entry.name) + "\n")
					continue
				}
				self.log(L("Downloading %@", url.lastPathComponent) + "\n")
				let zip = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
				if let data = try? Data(contentsOf: url), (try? data.write(to: zip)) != nil {
					self.run("/usr/bin/unzip", ["-q", "-o", zip.path, "-d", destination.path])
					try? FileManager.default.removeItem(at: zip)
				} else {
					DispatchQueue.main.async { self.output(L("Couldn't download %@", url.absoluteString) + "\n", true) }
				}
				DispatchQueue.main.async { self.progress(Double(index + 1) / Double(entries.count)) }
			}
			DispatchQueue.main.async { completion(destination) }
		}
	}

	/// Clones and builds each entry (Debug and Release) into Desktop/Hackintool_Build.
	/// Lilu is always built first because its plugins link against it.
	func build(_ entries: [KextEntry], lilu: KextEntry?, completion: @escaping (URL) -> Void) {
		let buildURL = KextJobs.desktop.appendingPathComponent("Hackintool_Build")
		let debugURL = buildURL.appendingPathComponent("Debug")
		let releaseURL = buildURL.appendingPathComponent("Release")
		let targets = entries.filter { !$0.isLilu && $0.repository != nil && $0.superseder == nil }

		DispatchQueue.global(qos: .userInitiated).async {
			let fileManager = FileManager.default
			[debugURL, releaseURL].forEach { try? fileManager.createDirectory(at: $0, withIntermediateDirectories: true) }
			// Lets Xcode's "clean" remove the folder's contents.
			self.run("/usr/bin/xattr", ["-w", "-r", "com.apple.xcode.CreatedByBuildSystem", "true", buildURL.path])

			let temp = fileManager.temporaryDirectory.appendingPathComponent("Hackintool-Build-\(UUID().uuidString)")
			let sdk = temp.appendingPathComponent("MacKernelSDK")
			self.run("/usr/bin/git", ["clone", "--depth", "1", "https://github.com/acidanthera/MacKernelSDK.git", sdk.path])

			let all = (lilu.map { [$0] } ?? []) + targets
			for (index, entry) in all.enumerated() {
				self.build(entry, in: buildURL, sdk: sdk, temp: temp, debugURL: debugURL, releaseURL: releaseURL)
				DispatchQueue.main.async { self.progress(Double(index + 1) / Double(all.count)) }
			}
			try? fileManager.removeItem(at: temp)
			DispatchQueue.main.async { completion(buildURL) }
		}
	}

	private func build(_ entry: KextEntry, in buildURL: URL, sdk: URL, temp: URL, debugURL: URL, releaseURL: URL) {
		let fileManager = FileManager.default
		let source = buildURL.appendingPathComponent(entry.name)
		try? fileManager.removeItem(at: source)

		run("/usr/bin/git", ["clone", entry.projectURL, source.path])
		run("/usr/bin/git", ["submodule", "update", "--init", "--recursive"], in: source.path)
		if entry.isLilu || entry.isLiluPlugin || entry.isAcidanthera {
			run("/bin/cp", ["-r", sdk.path, source.path])
		}
		if entry.isLiluPlugin {
			let lilu = source.appendingPathComponent("Lilu.kext")
			try? fileManager.removeItem(at: lilu)
			try? fileManager.copyItem(at: debugURL.appendingPathComponent("Lilu.kext"), to: lilu)
		}
		if let script = entry.preBuildBash {
			run("/bin/bash", ["-c", script.replacingOccurrences(of: "$(OUTPUT_PATH)", with: source.path)], in: source.path)
		}

		for (configuration, destination) in [("Debug", debugURL), ("Release", releaseURL)] {
			let products = temp.appendingPathComponent(configuration)
			var arguments = ["-project", source.appendingPathComponent(entry.projectFileName).path,
			                 "-configuration", configuration, "clean", "build", "ARCHS=x86_64",
			                 "CONFIGURATION_BUILD_DIR=" + products.path]
			if entry.isLilu {
				arguments.append("WARNING_CFLAGS=-w")
			}
			if let scheme = entry.scheme {
				arguments += ["-scheme", scheme]
			}
			guard run("/usr/bin/xcodebuild", arguments) == 0 else {
				log(L("Building %@ failed. See the output above.", "\(entry.name) (\(configuration))") + "\n")
				continue
			}
			run("/bin/cp", ["-r", products.path + "/.", destination.path])
		}
	}

	/// Building needs the Xcode command line tools.
	static var hasDeveloperTools: Bool {
		return Shell.run("/usr/bin/xcode-select", ["-p"])?.succeeded ?? false
	}

	static var desktop: URL {
		return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
	}
}
