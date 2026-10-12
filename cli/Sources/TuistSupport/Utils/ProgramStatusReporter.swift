import Foundation
import TuistConstants
import TuistEnvironment

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

/// Reports command state using the Program Status Protocol (OSC 7501).
/// https://www.superlogical.com/rex/docs/build/program-status
public struct ProgramStatusReporter: Sendable {
    public enum State: String, Sendable {
        case idle
        case working
        case done
        case blocked
        case error
    }

    public enum BlockedKind: String, Sendable {
        case permission
        case question
        case auth
    }

    @TaskLocal public static var current = ProgramStatusReporter(isEnabled: false)

    private let isEnabled: Bool
    private let write: @Sendable (String) throws -> Void

    public init() {
        self.init(isEnabled: Self.shouldReport(
            arguments: Environment.current.arguments,
            isInteractive: isatty(STDOUT_FILENO) != 0,
            isCI: Environment.current.isCI,
            terminalType: Environment.current.variables["TERM"],
            isQuiet: Environment.current.variables[Constants.EnvironmentVariables.quiet] != nil
        ))
    }

    public init(
        isEnabled: Bool,
        write: @escaping @Sendable (String) throws -> Void = {
            try FileHandle.standardOutput.write(contentsOf: Data($0.utf8))
        }
    ) {
        self.isEnabled = isEnabled
        self.write = write
    }

    static func shouldReport(
        arguments: [String],
        isInteractive: Bool,
        isCI: Bool,
        terminalType: String? = nil,
        isQuiet: Bool = false
    ) -> Bool {
        isInteractive && !isCI && !isQuiet && terminalType?.lowercased() != "dumb"
            && !MachineReadableOutput.isEnabled(arguments: arguments)
            && !MachineReadableOutput.isQuiet(arguments: arguments)
    }

    public func report(_ state: State, kind: BlockedKind? = nil, message: String? = nil) {
        guard isEnabled else { return }

        var pairs = "state=\(state.rawValue):app=tuist"
        if state == .blocked, let kind {
            pairs += ":kind=\(kind.rawValue)"
        }
        if let message {
            pairs += ":msg=\(Data(Self.sanitizedMessage(message).utf8).base64EncodedString())"
        }
        try? write("\u{1B}]7501;\(pairs)\u{1B}\\")
    }

    public func withCommandStatus<T>(_ operation: () async throws -> T) async rethrows -> T {
        report(.working, message: "Running Tuist")
        do {
            let result = try await operation()
            finish(exitCode: 0)
            return result
        } catch {
            finish(exitCode: 1, cancelled: error is CancellationError)
            throw error
        }
    }

    public func withBlockedStatus<T>(
        kind: BlockedKind,
        message: String,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        report(.blocked, kind: kind, message: message)
        defer { report(.working, message: "Running Tuist") }
        return try await operation()
    }

    /// Explicit exit paths must report before exiting, since they bypass Swift cleanup.
    public func finish(exitCode: Int32, cancelled: Bool = false) {
        if cancelled || exitCode == 130 {
            report(.idle, message: "Tuist cancelled")
        } else if exitCode == 0 {
            report(.done, message: "Tuist completed")
        } else {
            report(.error, message: "Tuist failed")
        }
    }

    private static func sanitizedMessage(_ message: String) -> String {
        var scalars = String.UnicodeScalarView()
        var byteCount = 0
        let forbiddenCharacters = CharacterSet.controlCharacters.union(.newlines)
        for scalar in message.unicodeScalars {
            let sanitized: Unicode.Scalar = forbiddenCharacters.contains(scalar) ? " " : scalar
            let size = sanitized.utf8.count
            guard byteCount + size <= 2048 else { break }
            scalars.append(sanitized)
            byteCount += size
        }
        return String(scalars)
    }
}
