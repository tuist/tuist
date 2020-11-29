import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// Saving frameworks installed using `carthage`.
public protocol CarthageFrameworksInteracting {
    /// Saves frameworks installed using `carthage`.
    /// - Parameters:
    ///   - carthageBuildDirectory: The path to the directory that contains the `Carthage/Build/` directory.
    ///   - destinationDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    func copyFrameworks(carthageBuildDirectory: AbsolutePath, destinationDirectory: AbsolutePath) throws
}

public final class CarthageFrameworksInteractor: CarthageFrameworksInteracting {
    private let fileHandler: FileHandling

    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }

    public func copyFrameworks(carthageBuildDirectory: AbsolutePath, destinationDirectory: AbsolutePath) throws {
        let versionFiles = try readVersionFiles(at: carthageBuildDirectory)

        try versionFiles.forEach {
            try $0.iOS?.forEach {
                let fromPath = carthageBuildDirectory.appending(components: "iOS", "\($0.name).framework")
                let toPath = destinationDirectory.appending(components: $0.name, "iOS", "\($0.name).framework")
                try copyDirectory(from: fromPath, to: toPath)
            }
            try $0.macOS?.forEach {
                let fromPath = carthageBuildDirectory.appending(components: "Mac", "\($0.name).framework")
                let toPath = destinationDirectory.appending(components: $0.name, "macOS", "\($0.name).framework")
                try copyDirectory(from: fromPath, to: toPath)
            }
            try $0.tvOS?.forEach {
                let fromPath = carthageBuildDirectory.appending(components: "tvOS", "\($0.name).framework")
                let toPath = destinationDirectory.appending(components: $0.name, "tvOS", "\($0.name).framework")
                try copyDirectory(from: fromPath, to: toPath)
            }
            try $0.watchOS?.forEach {
                let fromPath = carthageBuildDirectory.appending(components: "watchOS", "\($0.name).framework")
                let toPath = destinationDirectory.appending(components: $0.name, "watchOS", "\($0.name).framework")
                try copyDirectory(from: fromPath, to: toPath)
            }
        }
    }

    // MARK: - Helpers

    private func readVersionFiles(at path: AbsolutePath) throws -> [CarthageVersion] {
        let decoder = JSONDecoder()

        return try fileHandler
            .contentsOfDirectory(path)
            .filter { $0.extension == "version" }
            .map {
                let versionFileData = try fileHandler.readFile($0)
                return try decoder.decode(CarthageVersion.self, from: versionFileData)
            }
    }

    private func copyDirectory(from fromPath: AbsolutePath, to toPath: AbsolutePath) throws {
        try fileHandler.createFolder(toPath.removingLastComponent())

        if fileHandler.exists(toPath) {
            try fileHandler.delete(toPath)
        }

        try fileHandler.copy(from: fromPath, to: toPath)
    }
}

// MARK: - Models

private struct CarthageVersion: Decodable {
    enum CodingKeys: String, CodingKey {
        case commitish
        case iOS
        case macOS = "Mac"
        case tvOS
        case watchOS
    }

    struct Dependency: Decodable {
        let hash: String
        let name: String
        let linking: String
        let swiftToolchainVersion: String
    }

    let commitish: String
    let iOS: [Dependency]?
    let macOS: [Dependency]?
    let tvOS: [Dependency]?
    let watchOS: [Dependency]?
}
