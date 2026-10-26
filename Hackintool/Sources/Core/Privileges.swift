//
//  Privileges.swift
//  Hackintool
//
//  Administrator authorization and running tools as root.
//
//  The user unlocks once (toolbar lock or first admin command) and later commands
//  reuse that authorization. This uses AuthorizationExecuteWithPrivileges, as the
//  Objective-C app did; it's deprecated and hidden from Swift, so it's looked up at
//  runtime. It still works on current macOS and needs no privileged helper install.
//

import Foundation
import Security

final class Privileges {
	static let shared = Privileges()

	/// Posted on the main queue when the user grants administrator rights.
	static let didUnlockNotification = Notification.Name("PrivilegesDidUnlock")

	private var authorization: AuthorizationRef?
	private(set) var isUnlocked = false

	private typealias ExecuteWithPrivileges = @convention(c) (
		AuthorizationRef, UnsafePointer<CChar>, AuthorizationFlags,
		UnsafePointer<UnsafeMutablePointer<CChar>?>, UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
	) -> OSStatus

	private lazy var executeWithPrivileges: ExecuteWithPrivileges? = {
		guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "AuthorizationExecuteWithPrivileges") else { return nil }
		return unsafeBitCast(symbol, to: ExecuteWithPrivileges.self)
	}()

	private init() {}

	deinit {
		if let authorization = authorization {
			AuthorizationFree(authorization, [.destroyRights])
		}
	}

	/// Asks for administrator rights if not already granted. Returns whether they were granted.
	@discardableResult
	func unlock() -> Bool {
		if authorization == nil {
			var newAuthorization: AuthorizationRef?
			guard AuthorizationCreate(nil, nil, [], &newAuthorization) == errAuthorizationSuccess else { return false }
			authorization = newAuthorization
		}
		guard let authorization = authorization else { return false }

		let status: OSStatus = "system.privilege.admin".withCString { rightName in
			var item = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
			return withUnsafeMutablePointer(to: &item) { itemPointer in
				var rights = AuthorizationRights(count: 1, items: itemPointer)
				return AuthorizationCopyRights(authorization, &rights, nil, [.preAuthorize, .interactionAllowed, .extendRights], nil)
			}
		}
		guard status == errAuthorizationSuccess else { return false }

		if !isUnlocked {
			isUnlocked = true
			DispatchQueue.main.async {
				NotificationCenter.default.post(name: Self.didUnlockNotification, object: self)
			}
		}
		return true
	}

	struct Result {
		let output: String
		let error: String
		let status: Int32

		var succeeded: Bool { return status == 0 }

		/// stderr if there is any, otherwise stdout, trimmed: the message to show the user.
		var message: String {
			return (error.isEmpty ? output : error).trimmingCharacters(in: .whitespacesAndNewlines)
		}
	}

	/// Runs a tool as root and waits for it to finish. Output is captured through temporary files.
	/// Returns nil if authorization was refused or the tool couldn't be started.
	@discardableResult
	func run(_ launchPath: String, _ arguments: [String] = []) -> Result? {
		guard unlock(), let authorization = authorization, let execute = executeWithPrivileges else { return nil }

		let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Hackintool-\(UUID().uuidString)")
		guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return nil }
		defer { try? FileManager.default.removeItem(at: directory) }

		let stdoutPath = directory.appendingPathComponent("stdout").path
		let stderrPath = directory.appendingPathComponent("stderr").path
		let statusPath = directory.appendingPathComponent("status").path

		// sh -c '"$@" >out 2>err; echo $? >status' sh <tool> <args...>: the shell's own stdout is the
		// pipe we're handed, which closes when the shell exits, so reading it to EOF waits for the tool.
		let script = "\"$@\" 1>'\(stdoutPath)' 2>'\(stderrPath)'; echo $? >'\(statusPath)'"
		let shellArguments = ["-c", script, "sh", launchPath] + arguments

		var cArguments = shellArguments.map { strdup($0) }
		cArguments.append(nil)
		defer { cArguments.forEach { free($0) } }

		var pipe: UnsafeMutablePointer<FILE>?
		let launchStatus = cArguments.withUnsafeBufferPointer { buffer in
			execute(authorization, "/bin/sh", [], buffer.baseAddress!, &pipe)
		}
		guard launchStatus == errAuthorizationSuccess else { return nil }

		if let pipe = pipe {
			let handle = FileHandle(fileDescriptor: fileno(pipe), closeOnDealloc: false)
			_ = handle.readDataToEndOfFile()
			fclose(pipe)
		}

		let output = (try? String(contentsOfFile: stdoutPath, encoding: .utf8)) ?? ""
		let error = (try? String(contentsOfFile: stderrPath, encoding: .utf8)) ?? ""
		let status = (try? String(contentsOfFile: statusPath, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? -1
		return Result(output: output, error: error, status: status)
	}
}
