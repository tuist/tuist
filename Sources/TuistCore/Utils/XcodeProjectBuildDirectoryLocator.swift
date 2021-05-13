import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

public protocol XcodeProjectBuildDirectoryLocating {
    /// Locates the build output directory for `xcodebuild` command.
    ///
    /// For example: `~/Library/Developer/Xcode/DerivedData/PROJECT_NAME/Build/Products/CONFIG_NAME`
    ///
    /// - Parameters:
    ///   - platform: The platform for the built scheme.
    ///   - projectPath: The path of the Xcode project or workspace.
    ///   - configuration: The configuration name, i.e. `Release`, `Debug`, or something custom.
    func locate(
        platform: Platform,
        projectPath: AbsolutePath,
        configuration: String
    ) throws -> AbsolutePath
}

public final class XcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating {
    private let derivedDataLocator: DerivedDataLocating

    public init(derivedDataLocator: DerivedDataLocating = DerivedDataLocator()) {
        self.derivedDataLocator = derivedDataLocator
    }

    public func locate(
        platform: Platform,
        projectPath: AbsolutePath,
        configuration: String
    ) throws -> AbsolutePath {
        let configSDKPathComponent: String = {
            guard platform != .macOS else {
                return configuration
            }
            return "\(configuration)-\(platform.xcodeSimulatorSDK!)"
        }()

        return try derivedDataLocator.locate(for: projectPath)
            .appending(component: "Build")
            .appending(component: "Products")
            .appending(component: configSDKPathComponent)
    }
}
