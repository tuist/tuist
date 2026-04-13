import FileSystem
import Foundation
import Mockable
import Path
import TuistSimulator
import TuistSupport
import XcodeGraph

public enum BuildProductServiceError: Equatable, LocalizedError {
    case noAppsFound(app: String, configuration: String)
    case multipleBuiltBundlesFound(app: String, paths: [String])

    public var errorDescription: String? {
        switch self {
        case let .noAppsFound(app, configuration):
            "\(app) was not found in Xcode build products for the \(configuration) configuration. Build the app first or pass an explicit bundle path."
        case let .multipleBuiltBundlesFound(app, paths):
            "Multiple built bundles were found for \(app): \(paths.joined(separator: ", ")). Pass an explicit bundle path."
        }
    }
}

@Mockable
public protocol BuildProductServicing {
    func appBundles(
        app: String,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String,
        platforms: [Platform]
    ) async throws -> [AppBundle]

    func appBundlePath(
        app: String,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String,
        platforms: [Platform]
    ) async throws -> AbsolutePath
}

public struct BuildProductService: BuildProductServicing {
    private let fileSystem: FileSysteming
    private let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating
    private let appBundleLoader: AppBundleLoading

    public init(
        fileSystem: FileSysteming = FileSystem(),
        xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating = XcodeProjectBuildDirectoryLocator(),
        appBundleLoader: AppBundleLoading = AppBundleLoader()
    ) {
        self.fileSystem = fileSystem
        self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
        self.appBundleLoader = appBundleLoader
    }

    public func appBundles(
        app: String,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String,
        platforms: [Platform]
    ) async throws -> [AppBundle] {
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
            return try await appBundleLoader.load(appPath, destinationType: destinationType)
        }
    }

    public func appBundlePath(
        app: String,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String,
        platforms: [Platform]
    ) async throws -> AbsolutePath {
        let appPaths = try await appBundles(
            app: app,
            projectPath: projectPath,
            derivedDataPath: derivedDataPath,
            configuration: configuration,
            platforms: platforms
        )
        .map(\.path)

        guard !appPaths.isEmpty else {
            throw BuildProductServiceError.noAppsFound(app: app, configuration: configuration)
        }

        let uniquePaths = Array(Set(appPaths)).sorted { $0.pathString < $1.pathString }
        guard uniquePaths.count == 1, let bundlePath = uniquePaths.first else {
            throw BuildProductServiceError.multipleBuiltBundlesFound(
                app: app,
                paths: uniquePaths.map(\.pathString)
            )
        }

        return bundlePath
    }
}
