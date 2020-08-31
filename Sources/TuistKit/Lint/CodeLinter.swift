import Foundation
import TSCBasic
import TuistCore
import TuistSupport

protocol CodeLinting {
    func lint(sources: AbsolutePath, path: AbsolutePath) throws
}

class CodeLinter: CodeLinting {
    private let rootDirectoryLocator: RootDirectoryLocating
    private let binaryLocator: BinaryLocating

    init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
         binaryLocator: BinaryLocating = BinaryLocator())
    {
        self.rootDirectoryLocator = rootDirectoryLocator
        self.binaryLocator = binaryLocator
    }

    // MARK: - CodeLinting

    func lint(sources: AbsolutePath, path: AbsolutePath) throws {
        let swiftLintPath = try binaryLocator.swiftLintPath()
        let swiftLintConfigPath = self.swiftLintConfigPath(path: path)
        let swiftLintArguments = buildSwiftLintArguments(swiftLintPath: swiftLintPath,
                                                         sources: sources,
                                                         configPath: swiftLintConfigPath)

        _ = try System.shared.observable(swiftLintArguments)
            .mapToString()
            .printStandardError()
            .toBlocking()
            .last()
    }

    // MARK: - Helpers

    private func swiftLintConfigPath(path: AbsolutePath) -> AbsolutePath? {
        guard let rootPath = rootDirectoryLocator.locate(from: path) else { return nil }

        return ["yml", "yaml"].compactMap { (fileExtension) -> AbsolutePath? in
            let swiftlintPath = rootPath.appending(RelativePath("\(Constants.tuistDirectoryName)/swiftlint.\(fileExtension)"))
            return (FileHandler.shared.exists(swiftlintPath)) ? swiftlintPath : nil
        }.first
    }

    private func buildSwiftLintArguments(swiftLintPath: AbsolutePath, sources: AbsolutePath, configPath: AbsolutePath?) -> [String] {
        var arguments = [swiftLintPath.pathString, "lint", sources.pathString]

        if let configPath = configPath {
            arguments += ["--config", configPath.pathString]
        }

        return arguments
    }
}
