import Foundation
import Mockable
import Path
import TuistSimulator
import TuistSupport

@Mockable
public protocol XcodeProjectBuildDirectoryLocating {
    /// Locates the build output directory for `xcodebuild` command.
    ///
    /// For example: `~/Library/Developer/Xcode/DerivedData/PROJECT_NAME/Build/Products/CONFIG_NAME`
    ///
    /// - Parameters:
    ///   - destinationType: The destination platform for the built scheme.
    ///   - projectPath: The path of the Xcode project or workspace.
    ///   - derivedDataPath: The path of the derived data
    ///   - configuration: The configuration name, i.e. `Release`, `Debug`, or something custom.
    func locate(
        destinationType: DestinationType,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String
    ) async throws -> AbsolutePath
}

public final class XcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating {
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
            try await derivedDataLocator.locate(
                for: projectPath
            )
        }

        return derivedDataDirectory
            .appending(component: "Build")
            .appending(component: "Products")
            .appending(
                component: destinationType.buildProductDestinationPathComponent(
                    for: configuration
                )
            )
    }
}
