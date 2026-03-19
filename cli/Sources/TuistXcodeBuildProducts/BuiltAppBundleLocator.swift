import FileSystem
import Foundation
import Mockable
import Path
import TuistSimulator
import TuistSupport
import XcodeGraph

public struct BuiltAppBundle: Equatable, Sendable {
    public let destinationType: DestinationType
    public let path: AbsolutePath

    public init(destinationType: DestinationType, path: AbsolutePath) {
        self.destinationType = destinationType
        self.path = path
    }
}

public enum BuiltAppBundleLocatorError: Equatable, LocalizedError {
    case noAppsFound(app: String, configuration: String)
    case multipleBuiltBundlesFound(app: String, paths: [String])

    public var errorDescription: String? {
        switch self {
        case let .noAppsFound(app, configuration):
            "\(app) for the \(configuration) configuration was not found. You can build it by running `xcodebuild build -scheme \(app) -configuration \(configuration)`"
        case let .multipleBuiltBundlesFound(app, paths):
            "Multiple built bundles were found for \(app): \(paths.joined(separator: ", ")). Pass an explicit bundle path."
        }
    }
}

@Mockable
public protocol BuiltAppBundleLocating {
    func locateBuiltAppBundles(
        app: String,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String,
        platforms: [Platform]
    ) async throws -> [BuiltAppBundle]

    func locateBuiltAppBundlePath(
        app: String,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String,
        platforms: [Platform]
    ) async throws -> AbsolutePath
}

public struct BuiltAppBundleLocator: BuiltAppBundleLocating {
    private let fileSystem: FileSysteming
    private let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating

    public init(
        fileSystem: FileSysteming = FileSystem(),
        xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating = XcodeProjectBuildDirectoryLocator()
    ) {
        self.fileSystem = fileSystem
        self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
    }

    public func locateBuiltAppBundles(
        app: String,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String,
        platforms: [Platform]
    ) async throws -> [BuiltAppBundle] {
        let destinationTypes = platforms.flatMap { platform -> [DestinationType] in
            switch platform {
            case .iOS, .tvOS, .visionOS, .watchOS:
                return [
                    .simulator(platform),
                    .device(platform),
                ]
            case .macOS:
                return [.device(platform)]
            }
        }

        return try await destinationTypes.concurrentCompactMap { destinationType in
            let buildDirectory = try await xcodeProjectBuildDirectoryLocator.locate(
                destinationType: destinationType,
                projectPath: projectPath,
                derivedDataPath: derivedDataPath,
                configuration: configuration
            )
            let appPath = buildDirectory.appending(component: "\(app).app")
            guard try await fileSystem.exists(appPath) else { return nil }
            return BuiltAppBundle(destinationType: destinationType, path: appPath)
        }
    }

    public func locateBuiltAppBundlePath(
        app: String,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String,
        platforms: [Platform]
    ) async throws -> AbsolutePath {
        let appPaths = try await locateBuiltAppBundles(
            app: app,
            projectPath: projectPath,
            derivedDataPath: derivedDataPath,
            configuration: configuration,
            platforms: platforms
        )
        .map(\.path)

        guard !appPaths.isEmpty else {
            throw BuiltAppBundleLocatorError.noAppsFound(app: app, configuration: configuration)
        }

        let uniquePaths = Array(Set(appPaths)).sorted { $0.pathString < $1.pathString }
        guard uniquePaths.count == 1, let bundlePath = uniquePaths.first else {
            throw BuiltAppBundleLocatorError.multipleBuiltBundlesFound(
                app: app,
                paths: uniquePaths.map(\.pathString)
            )
        }

        return bundlePath
    }
}
