import Subprocess

enum SubprocessRunnerError: Error {
    case executionFailed
}

enum SubprocessRunner {
    static func capture(arguments: [String]) async throws -> String {
        guard let executable = arguments.first else { throw SubprocessRunnerError.executionFailed }

        let result = try await run(
            .name(executable),
            arguments: Arguments(Array(arguments.dropFirst())),
            output: .string(limit: 10 * 1024 * 1024),
            error: .string(limit: 10 * 1024 * 1024)
        )
        guard result.terminationStatus.isSuccess else { throw SubprocessRunnerError.executionFailed }
        return result.standardOutput ?? ""
    }
}
