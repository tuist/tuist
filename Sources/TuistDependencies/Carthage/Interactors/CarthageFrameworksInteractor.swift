import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// Saving frameworks installed using `carthage`.
public protocol CarthageFrameworksInteracting {
    /// Saves frameworks installed using `carthage`.
    /// - Parameters:
    ///   - carthageBuildDirectory: The path to the directory that contains frameworks built by Carthage.
    ///   - destinationDirectory: The path to the directory where frameworks built by Carthage should be saved.
    func copyFrameworks(carthageBuildDirectory: AbsolutePath, destinationDirectory: AbsolutePath) throws
}

public final class CarthageFrameworksInteractor: CarthageFrameworksInteracting {
    private let fileHandler: FileHandling

    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }

    public func copyFrameworks(carthageBuildDirectory: AbsolutePath, destinationDirectory: AbsolutePath) throws {
        let alreadyInstalledFrameworks: Set<String> = try getAlreadyInstalledFrameworkNames(at: destinationDirectory)
        
        try Platform.allCases.forEach { platform in
            let carthagePlatfromBuildsDirectory = carthageBuildDirectory.appending(component: platform.carthageDirectory)
            guard fileHandler.exists(carthagePlatfromBuildsDirectory) else { return }
            
            var newInstalledFrameworks = Set<String>()

            try fileHandler
                .contentsOfDirectory(carthagePlatfromBuildsDirectory)
                .filter { $0.isFolder && $0.extension == "framework" }
                .compactMap { $0.components.last?.components(separatedBy: ".").first }
                .forEach { frameworkName in
                    let carthageBuildFrameworkPath = carthagePlatfromBuildsDirectory.appending(component: "\(frameworkName).framework")
                    let destinationFrameworkPath = destinationDirectory.appending(components: frameworkName, platform.caseValue, "\(frameworkName).framework")
                    try copyDirectory(from: carthageBuildFrameworkPath, to: destinationFrameworkPath)
                    
                    newInstalledFrameworks.insert(frameworkName)
                }
            
            try alreadyInstalledFrameworks
                .subtracting(newInstalledFrameworks)
                .forEach { frameworkName in
                    let frameworkPath = destinationDirectory.appending(component: frameworkName)
                    let frameworkPlatformPath = frameworkPath.appending(component: platform.caseValue)

                    if fileHandler.exists(frameworkPlatformPath) {
                        try fileHandler.delete(frameworkPlatformPath)

                        if try fileHandler.contentsOfDirectory(frameworkPath).isEmpty {
                            try fileHandler.delete(frameworkPath)
                        }
                    }
                }
        }
    }

    // MARK: - Helpers

    private func getAlreadyInstalledFrameworkNames(at destinationDirectory: AbsolutePath) throws -> Set<String> {
        guard fileHandler.exists(destinationDirectory) else { return Set<String>() }
        
        return try fileHandler
            .contentsOfDirectory(destinationDirectory)
            .filter { $0.isFolder && $0.basename != "Build" }
            .map { $0.basename }
            .reduce(into: Set<String>()) { $0.insert($1) }
    }
    
    private func copyDirectory(from fromPath: AbsolutePath, to toPath: AbsolutePath) throws {
        try fileHandler.createFolder(toPath.removingLastComponent())

        if fileHandler.exists(toPath) {
            try fileHandler.delete(toPath)
        }

        try fileHandler.copy(from: fromPath, to: toPath)
    }
}
