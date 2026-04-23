import Path
import TuistEnvironment

public enum CommandArguments {
    public static func processArguments(_ arguments: [String]? = nil) -> [String]? {
        let arguments = arguments ?? Array(Environment.current.arguments)
        return arguments.filter { $0 != "--verbose" && $0 != "--quiet" }
    }

    public static func value(
        for optionNames: [String],
        in arguments: [String]
    ) -> String? {
        for optionName in optionNames {
            guard let optionIndex = arguments.firstIndex(of: optionName),
                  arguments.endIndex > optionIndex + 1
            else { continue }
            return arguments[optionIndex + 1]
        }

        return nil
    }

    public static func pathArgument(in arguments: [String]) -> String? {
        value(for: ["--path", "-p"], in: arguments)
    }

    public static func path(in arguments: [String]) async throws -> AbsolutePath {
        try await Environment.current.pathRelativeToWorkingDirectory(pathArgument(in: arguments))
    }
}
