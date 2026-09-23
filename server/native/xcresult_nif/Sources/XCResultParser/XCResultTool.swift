import Darwin
import Foundation

public struct XCResultToolOutput: Sendable {
    public let standardOutput: String
    public let standardError: String
    public let succeeded: Bool

    public init(standardOutput: String, standardError: String, succeeded: Bool) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.succeeded = succeeded
    }
}

/// The parser invokes Xcode tools at this boundary so parser tests can provide fixture output.
public typealias XCResultToolExecuting = @Sendable ([String]) async throws -> XCResultToolOutput

public func executeXCResultTool(_ arguments: [String]) async throws -> XCResultToolOutput {
    guard let executableName = arguments.first else {
        throw XCResultToolError.missingExecutable
    }

    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: outputURL)
        try? FileManager.default.removeItem(at: errorURL)
    }

    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    let outputHandle = try FileHandle(forWritingTo: outputURL)
    let errorHandle = try FileHandle(forWritingTo: errorURL)
    defer {
        try? outputHandle.close()
        try? errorHandle.close()
    }

    let process = XCResultToolProcess()
    if executableName.contains("/") {
        try await process.run(
            executableURL: URL(fileURLWithPath: executableName),
            arguments: Array(arguments.dropFirst()),
            standardOutput: outputHandle,
            standardError: errorHandle
        )
    } else {
        try await process.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: arguments,
            standardOutput: outputHandle,
            standardError: errorHandle
        )
    }

    return XCResultToolOutput(
        standardOutput: try String(contentsOf: outputURL, encoding: .utf8),
        standardError: try String(contentsOf: errorURL, encoding: .utf8),
        succeeded: process.terminationStatus == 0
    )
}

private final class XCResultToolProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var processIdentifier: pid_t?
    private var isCancelled = false

    private(set) var terminationStatus: Int32 = -1

    func run(
        executableURL: URL,
        arguments: [String],
        standardOutput: FileHandle,
        standardError: FileHandle
    ) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    let processIdentifier = try spawn(
                        executableURL: executableURL,
                        arguments: arguments,
                        standardOutput: standardOutput,
                        standardError: standardError
                    )
                    lock.withLock {
                        self.processIdentifier = processIdentifier
                        if isCancelled {
                            kill(processIdentifier, SIGKILL)
                        }
                    }
                    DispatchQueue.global().async {
                        do {
                            self.terminationStatus = try self.waitForExit(of: processIdentifier)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            lock.withLock {
                isCancelled = true
                if let processIdentifier {
                    kill(processIdentifier, SIGKILL)
                }
            }
        }
    }

    private func spawn(
        executableURL: URL,
        arguments: [String],
        standardOutput: FileHandle,
        standardError: FileHandle
    ) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            throw POSIXError(.EIO)
        }
        defer { posix_spawnattr_destroy(&attributes) }
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        sigdelset(&defaultSignals, SIGKILL)
        sigdelset(&defaultSignals, SIGSTOP)
        var signalMask = sigset_t()
        sigemptyset(&signalMask)
        guard posix_spawnattr_setsigmask(&attributes, &signalMask) == 0,
              posix_spawnattr_setsigdefault(&attributes, &defaultSignals) == 0,
              posix_spawnattr_setflags(
                  &attributes,
                  Int16(POSIX_SPAWN_START_SUSPENDED | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
              ) == 0
        else {
            throw POSIXError(.EIO)
        }

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            throw POSIXError(.EIO)
        }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawn_file_actions_adddup2(&actions, standardOutput.fileDescriptor, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, standardError.fileDescriptor, STDERR_FILENO) == 0
        else {
            throw POSIXError(.EIO)
        }

        let command = [executableURL.path] + arguments
        let commandPointers = command.map { strdup($0) }
        defer { commandPointers.forEach { free($0) } }
        var argv = commandPointers + [nil]
        var processIdentifier: pid_t = 0
        let result = posix_spawn(
            &processIdentifier,
            executableURL.path,
            &actions,
            &attributes,
            &argv,
            environ
        )
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO)
        }

        let queue = kqueue()
        guard queue >= 0 else {
            kill(processIdentifier, SIGKILL)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        lock.withLock {
            exitQueue = queue
        }

        var change = kevent()
        change.ident = UInt(processIdentifier)
        change.filter = Int16(EVFILT_PROC)
        change.flags = UInt16(EV_ADD | EV_ENABLE)
        change.fflags = NOTE_EXIT | UInt32(NOTE_EXITSTATUS)
        guard kevent(queue, &change, 1, nil, 0, nil) == 0 else {
            close(queue)
            kill(processIdentifier, SIGKILL)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        kill(processIdentifier, SIGCONT)
        return processIdentifier
    }

    private var exitQueue: Int32?

    private func waitForExit(of processIdentifier: pid_t) throws -> Int32 {
        guard let queue = lock.withLock({ exitQueue }) else {
            throw POSIXError(.EIO)
        }
        defer {
            close(queue)
            lock.withLock {
                exitQueue = nil
                self.processIdentifier = nil
            }
        }

        var event = kevent()
        guard kevent(queue, nil, 0, &event, 1, nil) == 1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard event.ident == UInt(processIdentifier), event.filter == Int16(EVFILT_PROC) else {
            throw POSIXError(.EIO)
        }
        return Int32(event.data)
    }
}

public enum XCResultToolError: Error, LocalizedError {
    case missingExecutable
    case terminated(command: [String], standardError: String)

    public var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "The command is missing an executable name."
        case let .terminated(command, standardError):
            let description = "The command '\(command.joined(separator: " "))' terminated unsuccessfully"
            let trimmedStandardError = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedStandardError.isEmpty ? description : "\(description):\n\(trimmedStandardError)"
        }
    }
}

extension XCResultToolOutput {
    func requireSuccess(for command: [String]) throws {
        guard succeeded else {
            throw XCResultToolError.terminated(command: command, standardError: standardError)
        }
    }
}
