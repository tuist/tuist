import Foundation
import Subprocess

enum SubprocessRunnerError: Error, CustomStringConvertible, LocalizedError {
    case missingExecutableName
    case terminated(Int32, stderr: String, command: [String])
    case signalled(Int32, command: [String])

    var description: String {
        switch self {
        case .missingExecutableName:
            return "The command is missing an executable name."
        case let .terminated(exitCode, stderr, command):
            let commandDescription = command.joined(separator: " ")
            let trimmedStandardError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = "The command '\(commandDescription)' terminated with the code \(exitCode)"
            return trimmedStandardError.isEmpty ? description : "\(description):\n\(trimmedStandardError)"
        case let .signalled(signal, command):
            return "The command '\(command.joined(separator: " "))' terminated after receiving a signal with code \(signal)"
        }
    }

    var errorDescription: String? { description }
}

enum SubprocessRunner {
    static func capture(arguments: [String]) async throws -> String {
        guard let executable = arguments.first else { throw SubprocessRunnerError.missingExecutableName }

        let result = try await run(
            .name(executable),
            arguments: Arguments(Array(arguments.dropFirst())),
            output: .string(limit: 10 * 1024 * 1024),
            error: .string(limit: 10 * 1024 * 1024)
        )
        guard result.terminationStatus.isSuccess else {
            switch result.terminationStatus {
            case let .exited(exitCode):
                throw SubprocessRunnerError.terminated(
                    exitCode,
                    stderr: result.standardError ?? "",
                    command: arguments
                )
            #if !os(Windows)
                case let .signaled(signal):
                    throw SubprocessRunnerError.signalled(signal, command: arguments)
            #endif
            }
        }
        return result.standardOutput ?? ""
    }
}
