import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// Saving frameworks installed using `carthage`.
public protocol CarthageFrameworksInteracting {
    /// Saves frameworks installed using `carthage`.
    /// - Parameters:
    ///   - carthageBuildDirectory: The path to the directory that contains the `Carthage/Build/` directory.
    ///   - destinationDirectory: The path to the directory that contains the `Tuist/Dependencies/Carthage` directory.
    func copyFrameworks(carthageBuildDirectory: AbsolutePath, destinationDirectory: AbsolutePath) throws
}

public final class CarthageFrameworksInteractor: CarthageFrameworksInteracting {
    private let fileHandler: FileHandling

    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }

    public func copyFrameworks(carthageBuildDirectory: AbsolutePath, destinationDirectory: AbsolutePath) throws {
        try Platform.allCases.forEach { platform in
            let carthagePlatfromBuildsDirectory = carthageBuildDirectory.appending(component: platform.carthageDirectory)
            guard fileHandler.exists(carthagePlatfromBuildsDirectory) else { return }

            try fileHandler
                .contentsOfDirectory(carthagePlatfromBuildsDirectory)
                .filter { $0.isFolder && $0.extension == "framework" }
                .compactMap { $0.components.last?.components(separatedBy: ".").first }
                .forEach { frameworkName in
                    let carthageBuildFrameworkPath = carthagePlatfromBuildsDirectory.appending(component: "\(frameworkName).framework")
                    let destinationFramemorekPath = destinationDirectory.appending(components: frameworkName, platform.caseValue, "\(frameworkName).framework")
                    try copyDirectory(from: carthageBuildFrameworkPath, to: destinationFramemorekPath)
                }
        }
    }

    // MARK: - Helpers

    private func copyDirectory(from fromPath: AbsolutePath, to toPath: AbsolutePath) throws {
        try fileHandler.createFolder(toPath.removingLastComponent())

        if fileHandler.exists(toPath) {
            try fileHandler.delete(toPath)
        }

        try fileHandler.copy(from: fromPath, to: toPath)
    }
}
