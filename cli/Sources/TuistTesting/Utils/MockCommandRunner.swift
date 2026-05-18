import Command
import Foundation
import Path

public final class MockCommandRunner: CommandRunning, @unchecked Sendable {
    public var env: [String: String] = [:]

    private let lock = NSLock()

    // swiftlint:disable:next large_tuple
    private var _defaultCaptureStubs: (stderror: String?, stdout: String?, exitstatus: Int?)?
    // swiftlint:disable:next large_tuple
    private var _captureStubs: [String: (stderror: String?, stdout: String?, exitstatus: Int?)] = [:]
    private var _calls: [String] = []
    public var whichStub: ((String) throws -> String?)?

    // swiftlint:disable:next large_tuple
    public var defaultCaptureStubs: (stderror: String?, stdout: String?, exitstatus: Int?)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _defaultCaptureStubs
        }
        set {
            lock.lock()
            _defaultCaptureStubs = newValue
            lock.unlock()
        }
    }

    public var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    public init() {}

    public func succeedCommand(_ arguments: [String], output: String? = nil, error: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        _captureStubs[arguments.joined(separator: " ")] = (stderror: error, stdout: output, exitstatus: 0)
    }

    public func errorCommand(_ arguments: [String], error: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        _captureStubs[arguments.joined(separator: " ")] = (stderror: error, stdout: nil, exitstatus: 1)
    }

    public func called(_ args: [String]) -> Bool {
        let command = args.joined(separator: " ")
        lock.lock()
        defer { lock.unlock() }
        return _calls.contains(command)
    }

    public func run(
        arguments: [String],
        environment _: [String: String],
        workingDirectory _: Path.AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        AsyncThrowingStream { continuation in
            let command = arguments.joined(separator: " ")
            lock.lock()
            _calls.append(command)
            let stub = _captureStubs[command] ?? _defaultCaptureStubs
            lock.unlock()

            if arguments.count == 3, arguments[0] == "/usr/bin/env", arguments[1] == "which" {
                do {
                    if let path = try whichStub?(arguments[2]) {
                        continuation.yield(.standardOutput(Array(path.utf8)))
                        continuation.finish()
                    } else {
                        continuation.finish(
                            throwing: CommandError.executableNotFound(arguments[2])
                        )
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
                return
            }

            guard let stub else {
                continuation.finish(
                    throwing: CommandError.terminated(1, stderr: "", command: arguments)
                )
                return
            }

            if stub.exitstatus != 0 {
                continuation.finish(
                    throwing: CommandError.terminated(
                        Int32(stub.exitstatus ?? 1),
                        stderr: stub.stderror ?? "",
                        command: arguments
                    )
                )
                return
            }

            if let stdout = stub.stdout {
                continuation.yield(.standardOutput(Array(stdout.utf8)))
            }
            if let stderror = stub.stderror {
                continuation.yield(.standardError(Array(stderror.utf8)))
            }
            continuation.finish()
        }
    }
}
