import Foundation
import Path

/// Resolves the `index-import` and `absolute-unit` binaries used to slice and import index stores.
///
/// Both ship together in the `index-import` release. They are located, in order, from:
/// 1. the `TUIST_INDEX_IMPORT_DIRECTORY` environment override (used in tests and CI), then
/// 2. the directory next to the running `tuist` executable, where the release vendors them.
///
/// Returns `nil` when the tool cannot be found so index generation degrades to a no-op rather than
/// failing the surrounding cache command.
public enum IndexImportLocator {
    public static let environmentVariable = "TUIST_INDEX_IMPORT_DIRECTORY"

    public static func indexImportPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> AbsolutePath? {
        locate(tool: "index-import", environment: environment)
    }

    public static func absoluteUnitPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> AbsolutePath? {
        locate(tool: "absolute-unit", environment: environment)
    }

    private static func locate(tool: String, environment: [String: String]) -> AbsolutePath? {
        for directory in candidateDirectories(environment: environment) {
            let candidate = directory.appending(component: tool)
            if FileManager.default.isExecutableFile(atPath: candidate.pathString) {
                return candidate
            }
        }
        return nil
    }

    private static func candidateDirectories(environment: [String: String]) -> [AbsolutePath] {
        var directories: [AbsolutePath] = []
        if let override = environment[environmentVariable], let path = try? AbsolutePath(validating: override) {
            directories.append(path)
        }
        if let executablePath = Bundle.main.executablePath,
           let executableDirectory = try? AbsolutePath(validating: executablePath).parentDirectory
        {
            directories.append(executableDirectory)
        }
        return directories
    }
}
