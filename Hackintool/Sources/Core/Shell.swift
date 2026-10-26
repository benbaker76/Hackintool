//
//  Shell.swift
//  Hackintool
//
//  Running command-line tools, either to completion or streaming their output.
//

import Foundation

enum Shell {
	struct Result {
		let output: String
		let status: Int32

		var succeeded: Bool { return status == 0 }
	}

	/// Runs a tool to completion and returns its combined stdout and stderr.
	@discardableResult
	static func run(_ launchPath: String, _ arguments: [String] = [], currentDirectory: String = "/") -> Result? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: launchPath)
		process.arguments = arguments
		process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		do {
			try process.run()
		} catch {
			return nil
		}
		// Read before waiting so a full pipe buffer can't deadlock the child.
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return Result(output: String(decoding: data, as: UTF8.self), status: process.terminationStatus)
	}

	/// Convenience for tools whose output is all that matters.
	static func output(_ launchPath: String, _ arguments: [String] = []) -> String? {
		return run(launchPath, arguments)?.output
	}

	/// Runs a tool in the background, delivering stdout and stderr on the main queue as they arrive.
	/// Returns the running process so the caller can terminate it.
	@discardableResult
	static func stream(_ launchPath: String, _ arguments: [String], currentDirectory: String = "/",
	                   output: @escaping (String) -> Void, error: @escaping (String) -> Void,
	                   completion: @escaping (Int32) -> Void) -> Process? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: launchPath)
		process.arguments = arguments
		process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
		process.standardInput = Pipe()

		let outputPipe = Pipe()
		let errorPipe = Pipe()
		process.standardOutput = outputPipe
		process.standardError = errorPipe

		let group = DispatchGroup()
		func forward(_ pipe: Pipe, to handler: @escaping (String) -> Void) {
			group.enter()
			DispatchQueue.global(qos: .utility).async {
				let handle = pipe.fileHandleForReading
				while case let data = handle.availableData, !data.isEmpty {
					let text = String(decoding: data, as: UTF8.self)
					DispatchQueue.main.async { handler(text) }
				}
				group.leave()
			}
		}

		do {
			try process.run()
		} catch {
			return nil
		}
		forward(outputPipe, to: output)
		forward(errorPipe, to: error)

		DispatchQueue.global(qos: .utility).async {
			process.waitUntilExit()
			group.wait()
			let status = process.terminationStatus
			DispatchQueue.main.async { completion(status) }
		}
		return process
	}
}
