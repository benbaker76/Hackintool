//
//  GitHub.swift
//  Hackintool
//
//  Latest-release lookups through the GitHub API.
//

import Foundation

enum GitHub {
	struct Release {
		let tagName: String
		let assets: [Asset]

		/// The version from the tag, without a leading "v".
		var version: String {
			return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
		}

		func asset(prefix: String?, suffix: String?) -> Asset? {
			return assets.first { asset in
				(prefix.map { asset.name.hasPrefix($0) } ?? true) && (suffix.map { asset.name.hasSuffix($0) } ?? true)
			}
		}
	}

	struct Asset {
		let name: String
		let downloadURL: URL
		let size: Int
	}

	/// Fetches the latest release of owner/repository; calls back on the main queue.
	static func latestRelease(owner: String, repository: String, completion: @escaping (Release?) -> Void) {
		let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
		var request = URLRequest(url: url)
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		URLSession.shared.dataTask(with: request) { data, _, _ in
			let release = data.flatMap(parseRelease)
			DispatchQueue.main.async { completion(release) }
		}.resume()
	}

	/// owner/repository from a project URL such as https://github.com/acidanthera/Lilu.
	static func repository(from projectURL: String) -> (owner: String, repository: String)? {
		guard let url = URL(string: projectURL), url.host?.hasSuffix("github.com") == true else { return nil }
		let parts = url.pathComponents.filter { $0 != "/" }
		guard parts.count >= 2 else { return nil }
		return (parts[0], parts[1])
	}

	private static func parseRelease(_ data: Data) -> Release? {
		guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let tagName = json["tag_name"] as? String else { return nil }
		let assets = (json["assets"] as? [[String: Any]] ?? []).compactMap { asset -> Asset? in
			guard let name = asset["name"] as? String,
			      let urlString = asset["browser_download_url"] as? String,
			      let url = URL(string: urlString) else { return nil }
			return Asset(name: name, downloadURL: url, size: asset["size"] as? Int ?? 0)
		}
		return Release(tagName: tagName, assets: assets)
	}
}

enum VersionNumber {
	/// Compares dotted versions numerically: "1.10.0" > "1.9.2".
	static func isNewer(_ candidate: String, than current: String) -> Bool {
		let a = candidate.split(separator: ".").map { Int($0.filter { $0.isNumber }) ?? 0 }
		let b = current.split(separator: ".").map { Int($0.filter { $0.isNumber }) ?? 0 }
		for index in 0..<max(a.count, b.count) {
			let x = index < a.count ? a[index] : 0
			let y = index < b.count ? b[index] : 0
			if x != y {
				return x > y
			}
		}
		return false
	}
}
