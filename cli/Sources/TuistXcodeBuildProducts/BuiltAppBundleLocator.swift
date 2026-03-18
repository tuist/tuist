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

@Mockable
public protocol BuiltAppBundleLocating {
    func locateBuiltAppBundles(
        app: String,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String,
        platforms: [Platform]
    ) async throws -> [BuiltAppBundle]
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
}
