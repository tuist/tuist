import Foundation
import SwiftLintFramework
import TSCBasic
import TuistCore
import TuistSupport

protocol CodeLinting {
    func lint(sources: [AbsolutePath], path: AbsolutePath) throws
}

class CodeLinter: CodeLinting {
    private let rootDirectoryLocator: RootDirectoryLocating

    init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    // MARK: - CodeLinting

    func lint(sources _: [AbsolutePath], path: AbsolutePath) throws {
        let swiftlintConfigPath = self.swiftlintConfigPath(path: path)
        if swiftlintConfigPath == nil {
            logger.info("Swiftlint configuration not found under Tuist/ using Tuist's defaults.")
        }

        // https://github.com/realm/SwiftLint/blob/master/Source/swiftlint/Helpers/LintOrAnalyzeCommand.swift
    }

    private func swiftlintConfigPath(path: AbsolutePath) -> AbsolutePath? {
        guard let rootPath = rootDirectoryLocator.locate(from: path) else { return nil }
        return ["yml", "yaml"].compactMap { (fileExtension) -> AbsolutePath? in
            let swiftlintPath = rootPath.appending(RelativePath("\(Constants.tuistDirectoryName)/swiftlint.\(fileExtension)"))
            return (FileHandler.shared.exists(swiftlintPath)) ? swiftlintPath : nil
        }.first
    }
}
