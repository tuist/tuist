import Foundation
import RxBlocking
import TSCBasic
import TuistCore
import TuistSupport

public protocol CodeLinting {
    /// Lints source code in the given directory.
    /// - Parameters:
    ///   - sources: Directory in which source code will be linted.
    ///   - path: Directory whose project will be linted.
    ///   - strict: Bool if warnings should error.
    func lint(sources: [AbsolutePath], path: AbsolutePath, strict: Bool) throws
}

public final class CodeLinter: CodeLinting {
    private let rootDirectoryLocator: RootDirectoryLocating
    private let binaryLocator: BinaryLocating

    public init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
                binaryLocator: BinaryLocating = BinaryLocator())
    {
        self.rootDirectoryLocator = rootDirectoryLocator
        self.binaryLocator = binaryLocator
    }

    // MARK: - CodeLinting

    public func lint(sources: [AbsolutePath], path: AbsolutePath, strict: Bool) throws {
        let swiftLintPath = try binaryLocator.swiftLintPath()
        let swiftLintConfigPath = self.swiftLintConfigPath(path: path)
        let swiftLintArguments = buildSwiftLintArguments(
            swiftLintPath: swiftLintPath,
            sources: sources,
            configPath: swiftLintConfigPath,
            strict: strict
        )
        let environment = buildEnvironment(sources: sources)

        _ = try System.shared.observable(
            swiftLintArguments,
            verbose: false,
            environment: environment
        )
        .mapToString()
        .print()
        .toBlocking()
        .last()
    }

    // MARK: - Helpers

    private func swiftLintConfigPath(path: AbsolutePath) -> AbsolutePath? {
        guard let rootPath = rootDirectoryLocator.locate(from: path) else { return nil }
        return ["yml", "yaml"].compactMap { (fileExtension) -> AbsolutePath? in
            let swiftlintPath = rootPath.appending(RelativePath("\(Constants.tuistDirectoryName)/.swiftlint.\(fileExtension)"))
            return (FileHandler.shared.exists(swiftlintPath)) ? swiftlintPath : nil
        }.first
    }

    private func buildEnvironment(sources: [AbsolutePath]) -> [String: String] {
        var environment = ["SCRIPT_INPUT_FILE_COUNT": "\(sources.count)"]
        for source in sources.enumerated() {
            environment["SCRIPT_INPUT_FILE_\(source.offset)"] = source.element.pathString
        }
        return environment
    }

    private func buildSwiftLintArguments(swiftLintPath: AbsolutePath,
                                         sources _: [AbsolutePath],
                                         configPath: AbsolutePath?,
                                         strict: Bool) -> [String]
    {
        var arguments = [swiftLintPath.pathString,
                         "lint",
                         "--use-script-input-files"]

        if let configPath = configPath {
            arguments += ["--config", configPath.pathString]
        }

        if strict {
            arguments += ["--strict"]
        }

        return arguments
    }
}
