import ArgumentParser
import Path
import TuistEnvironment
import TuistSupport

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

    public static func path(in arguments: [String], command: ParsableCommand? = nil) async throws -> AbsolutePath {
        let path: String?
        if let command = command as? ProjectPathProviding {
            path = command.path
        } else {
            path = pathArgument(in: arguments)
        }
        return try await Environment.current.pathRelativeToWorkingDirectory(path)
    }
}
