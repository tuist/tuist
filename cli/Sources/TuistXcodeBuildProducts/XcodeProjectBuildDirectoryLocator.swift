import Foundation
import Mockable
import Path
import TuistSimulator

@Mockable
public protocol XcodeProjectBuildDirectoryLocating {
    func locate(
        destinationType: DestinationType,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String
    ) async throws -> AbsolutePath
}

public struct XcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating {
    private let derivedDataLocator: DerivedDataLocating

    public init(derivedDataLocator: DerivedDataLocating = DerivedDataLocator()) {
        self.derivedDataLocator = derivedDataLocator
    }

    public func locate(
        destinationType: DestinationType,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String
    ) async throws -> AbsolutePath {
        let derivedDataDirectory = if let derivedDataPath {
            derivedDataPath
        } else {
            try await derivedDataLocator.locate(for: projectPath)
        }

        return derivedDataDirectory
            .appending(component: "Build")
            .appending(component: "Products")
            .appending(
                component: destinationType.buildProductDestinationPathComponent(for: configuration)
            )
    }
}
