import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// Saving frameworks installed using `carthage`.
public protocol CarthageFrameworksInteracting {
    /// Saves frameworks installed using `carthage`.
    /// - Parameters:
    ///   - path: Directory whose project's dependencies will be installed.
    ///   - temporaryDirectoryPath: Folder where dependencies are being installed.
    func save(at path: AbsolutePath, temporaryDirectoryPath: AbsolutePath) throws
}

public final class CarthageFrameworksInteractor: CarthageFrameworksInteracting {
    private let fileHandler: FileHandling

    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }

    public func save(at path: AbsolutePath, temporaryDirectoryPath: AbsolutePath) throws {
        let buildDirectoryPath = temporaryDirectoryPath.appending(components: "Carthage", "Build")
        let dependenciesDirectoryPath = path.appending(components: Constants.tuistDirectoryName, Constants.DependenciesDirectory.name)

        let versionFiles = try readVersionFiles(at: buildDirectoryPath)

        var alreadyCopiediOSFramworks = Set<String>()
        var alreadyCopiedmacOSFramworks = Set<String>()
        var alreadyCopiedtvOSFramworks = Set<String>()
        var alreadyCopiedwatchOSFramworks = Set<String>()

        try versionFiles.forEach {
            try $0.iOS?.forEach {
                guard !alreadyCopiediOSFramworks.contains($0.name) else { return }

                let fromPath = buildDirectoryPath.appending(components: "iOS", "\($0.name).framework")
                let toPath = dependenciesDirectoryPath.appending(components: $0.name, "iOS", "\($0.name).framework")
                try copyDirectory(from: fromPath, to: toPath)

                alreadyCopiediOSFramworks.insert($0.name)
            }
            try $0.macOS?.forEach {
                guard !alreadyCopiedmacOSFramworks.contains($0.name) else { return }

                let fromPath = buildDirectoryPath.appending(components: "Mac", "\($0.name).framework")
                let toPath = dependenciesDirectoryPath.appending(components: $0.name, "macOS", "\($0.name).framework")
                try copyDirectory(from: fromPath, to: toPath)

                alreadyCopiedmacOSFramworks.insert($0.name)
            }
            try $0.tvOS?.forEach {
                guard !alreadyCopiedtvOSFramworks.contains($0.name) else { return }

                let fromPath = buildDirectoryPath.appending(components: "tvOS", "\($0.name).framework")
                let toPath = dependenciesDirectoryPath.appending(components: $0.name, "tvOS", "\($0.name).framework")
                try copyDirectory(from: fromPath, to: toPath)

                alreadyCopiedtvOSFramworks.insert($0.name)
            }
            try $0.watchOS?.forEach {
                guard !alreadyCopiedwatchOSFramworks.contains($0.name) else { return }

                let fromPath = buildDirectoryPath.appending(components: "watchOS", "\($0.name).framework")
                let toPath = dependenciesDirectoryPath.appending(components: $0.name, "watchOS", "\($0.name).framework")
                try copyDirectory(from: fromPath, to: toPath)

                alreadyCopiedwatchOSFramworks.insert($0.name)
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
