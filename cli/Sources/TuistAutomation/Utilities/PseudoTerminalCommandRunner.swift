import Command
import Foundation
import Path

#if canImport(Darwin)
    import Darwin
#endif

/// A `CommandRunning` implementation that connects the child process' standard output to a
/// pseudo-terminal instead of a pipe.
///
/// `xcodebuild test` with parallel testing enabled checks `isatty(stdout)` and, when it is not a
/// terminal, switches to application-level buffering that only flushes once the process exits. No
/// output is produced during the whole test-execution phase, which makes CI systems kill the job on
/// their no-output timeout. Running it attached to a pseudo-terminal makes `isatty` return true, so
/// the results stream in real time.
///
/// Standard error is kept on a regular pipe so the two streams stay distinguishable. If a
/// pseudo-terminal cannot be allocated, the runner transparently falls back to a regular pipe-based
/// execution, preserving the previous behavior.
public struct PseudoTerminalCommandRunner: CommandRunning, Sendable {
    private let fallbackRunner: CommandRunner

    public init() {
        fallbackRunner = CommandRunner()
    }

    public func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        #if os(macOS)
            let fallbackRunner = fallbackRunner
            return AsyncThrowingStream(CommandEvent.self, bufferingPolicy: .unbounded) { continuation in
                Task.detached {
                    do {
                        try PseudoTerminal.run(
                            arguments: arguments,
                            environment: environment,
                            workingDirectory: workingDirectory,
                            continuation: continuation
                        )
                        continuation.finish()
                    } catch PseudoTerminal.PseudoTerminalError.allocationFailed {
                        do {
                            for try await event in fallbackRunner.run(
                                arguments: arguments,
                                environment: environment,
                                workingDirectory: workingDirectory
                            ) {
                                continuation.yield(event)
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        #else
            return fallbackRunner.run(
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory
            )
        #endif
    }
}

#if os(macOS)
    private enum PseudoTerminal {
        enum PseudoTerminalError: Error {
            case allocationFailed
        }

        // swiftlint:disable:next function_body_length
        static func run(
            arguments: [String],
            environment: [String: String],
            workingDirectory: Path.AbsolutePath?,
            continuation: AsyncThrowingStream<CommandEvent, any Error>.Continuation
        ) throws {
            guard let executable = arguments.first else {
                throw CommandError.missingExecutableName
            }

            let primary = posix_openpt(O_RDWR | O_NOCTTY)
            guard primary >= 0, grantpt(primary) == 0, unlockpt(primary) == 0,
                  let secondaryNameC = ptsname(primary)
            else {
                if primary >= 0 { close(primary) }
                throw PseudoTerminalError.allocationFailed
            }
            let secondaryPath = String(cString: secondaryNameC)
            let secondary = open(secondaryPath, O_RDWR | O_NOCTTY)
            guard secondary >= 0 else {
                close(primary)
                throw PseudoTerminalError.allocationFailed
            }

            // Raw mode so the output isn't transformed (e.g. \n -> \r\n) or echoed back.
            var term = termios()
            if tcgetattr(secondary, &term) == 0 {
                cfmakeraw(&term)
                _ = tcsetattr(secondary, TCSANOW, &term)
            }

            let stderrPipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(arguments.dropFirst())
            process.environment = environment
            if let workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory.pathString)
            }
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle(fileDescriptor: secondary, closeOnDealloc: false)
            process.standardError = stderrPipe

            let collectedStandardError = Locked("")
            let boxedProcess = Locked(process)
            continuation.onTermination = { termination in
                if case .cancelled = termination {
                    let process = boxedProcess.value
                    if process.isRunning { process.terminate() }
                }
            }

            do {
                try process.run()
            } catch {
                close(secondary)
                close(primary)
                throw error
            }
            // The child now owns the secondary end; closing our copy lets reads on the primary end
            // observe EOF once the child exits.
            close(secondary)

            let stderrReadFileDescriptor = stderrPipe.fileHandleForReading.fileDescriptor
            let group = DispatchGroup()

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                readToEnd(fileDescriptor: primary) { bytes in
                    continuation.yield(.standardOutput(bytes))
                }
            }

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                readToEnd(fileDescriptor: stderrReadFileDescriptor) { bytes in
                    if let string = String(bytes: bytes, encoding: .utf8) {
                        collectedStandardError.mutate { $0 += string }
                    }
                    continuation.yield(.standardError(bytes))
                }
            }

            process.waitUntilExit()
            group.wait()
            close(primary)

            switch process.terminationReason {
            case .exit where process.terminationStatus != 0:
                throw CommandError.terminated(
                    process.terminationStatus,
                    stderr: collectedStandardError.value,
                    command: arguments
                )
            case .uncaughtSignal where process.terminationStatus != 0:
                throw CommandError.signalled(process.terminationStatus, command: arguments)
            default:
                break
            }
        }

        private static func readToEnd(fileDescriptor: Int32, onData: ([UInt8]) -> Void) {
            let bufferSize = 1 << 16
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
            defer { buffer.deallocate() }
            while true {
                let bytesRead = read(fileDescriptor, buffer, bufferSize)
                if bytesRead > 0 {
                    onData(Array(UnsafeRawBufferPointer(start: buffer, count: bytesRead)))
                } else if bytesRead == 0 {
                    break
                } else {
                    if errno == EINTR { continue }
                    break
                }
            }
        }
    }

    private final class Locked<Value>: @unchecked Sendable {
        private var _value: Value
        private let lock = NSLock()

        init(_ value: Value) { _value = value }

        var value: Value {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }

        func mutate(_ transform: (inout Value) -> Void) {
            lock.lock()
            transform(&_value)
            lock.unlock()
        }
    }
#endif
