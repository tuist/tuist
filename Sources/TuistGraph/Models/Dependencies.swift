import Foundation
import TSCBasic

/// Contains the description of a dependency that can be installed using Swift Package Manager.
public struct Dependencies: Equatable, Codable {
    /// The path to the `Package.swift` manifest defining the dependencies.
    public let package: AbsolutePath?

    /// The custom `Product` types to be used for SPM targets.
    public let productTypes: [String: Product]

    // The base settings to be used for targets generated from SwiftPackageManager
    public let baseSettings: Settings

    /// The custom `Settings` to be applied to SPM targets
    public let targetSettings: [String: SettingsDictionary]

    /// The custom project options for each project generated from a swift package
    public let projectOptions: [String: TuistGraph.Project.Options]

    /// Initializes a new `Dependencies` instance.
    /// - Parameters:
    ///    - package: path to the `Package.swift` manifest defining the dependencies.
    ///    - productTypes: The custom `Product` types to be used for SPM targets.
    ///    - baseSettings: The base settings to be used for targets generated from SwiftPackageManager
    ///    - targetSettings: The custom `SettingsDictionary` to be applied to denoted targets
    ///    - projectOptions: The custom project options for each project generated from a swift package

    public init(
        package: AbsolutePath?,
        productTypes: [String: Product],
        baseSettings: Settings,
        targetSettings: [String: SettingsDictionary],
        projectOptions: [String: TuistGraph.Project.Options] = [:]
    ) {
        self.package = package
        self.productTypes = productTypes
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
    }
}
