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

	/// Runs a tool to completion on the calling (background) thread, keeping only the last
	/// `maxBytes` of its combined output, for tools like `log show` that can print gigabytes.
	/// `started` gets the process so the caller can terminate it; `progress` gets the number
	/// of bytes read so far, every few megabytes.
	static func tail(_ launchPath: String, _ arguments: [String], maxBytes: Int,
	                 started: (Process) -> Void = { _ in },
	                 progress: (Int) -> Void = { _ in }) -> (output: String, totalBytes: Int)? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: launchPath)
		process.arguments = arguments
		process.standardInput = FileHandle.nullDevice
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		do {
			try process.run()
		} catch {
			return nil
		}
		started(process)
		let handle = pipe.fileHandleForReading
		var buffer = Data()
		var total = 0
		var reported = 0
		// Plain read(2) into one chunk: availableData autoreleases every chunk it returns.
		var chunk = [UInt8](repeating: 0, count: 64 << 10)
		let fd = handle.fileDescriptor
		while true {
			let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
			if count < 0 && errno == EINTR { continue }
			guard count > 0 else { break }
			buffer.append(contentsOf: chunk[0..<count])
			total += count
			// Trim only once the buffer doubles, so the copying stays linear. subdata copies;
			// a suffix slice would keep the whole storage alive.
			if buffer.count > maxBytes * 2 {
				buffer = buffer.subdata(in: buffer.endIndex - maxBytes..<buffer.endIndex)
			}
			if total - reported >= 8 << 20 {
				reported = total
				progress(total)
			}
		}
		process.waitUntilExit()
		if buffer.count > maxBytes {
			buffer = buffer.suffix(maxBytes)
		}
		// Start on a whole line when the head was cut off.
		if total > buffer.count, let newline = buffer.firstIndex(of: 0x0A) {
			buffer = buffer.suffix(from: buffer.index(after: newline))
		}
		return (String(decoding: buffer, as: UTF8.self), total)
	}

	/// Runs a tool to completion on the calling (background) thread, passing output to
	/// `output` on the main queue as it arrives. `isError` marks stderr.
	@discardableResult
	static func runStreaming(_ launchPath: String, _ arguments: [String], currentDirectory: String = "/",
	                         output: @escaping (_ text: String, _ isError: Bool) -> Void) -> Int32 {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: launchPath)
		process.arguments = arguments
		process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
		process.standardInput = FileHandle.nullDevice
		let outputPipe = Pipe()
		let errorPipe = Pipe()
		process.standardOutput = outputPipe
		process.standardError = errorPipe

		let group = DispatchGroup()
		for (pipe, isError) in [(outputPipe, false), (errorPipe, true)] {
			group.enter()
			DispatchQueue.global(qos: .utility).async {
				let handle = pipe.fileHandleForReading
				while case let data = handle.availableData, !data.isEmpty {
					let text = String(decoding: data, as: UTF8.self)
					DispatchQueue.main.async { output(text, isError) }
				}
				group.leave()
			}
		}
		do {
			try process.run()
		} catch {
			DispatchQueue.main.async { output("\(launchPath): \(error.localizedDescription)\n", true) }
			outputPipe.fileHandleForWriting.closeFile()
			errorPipe.fileHandleForWriting.closeFile()
			group.wait()
			return -1
		}
		process.waitUntilExit()
		group.wait()
		return process.terminationStatus
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
