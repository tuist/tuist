import Foundation

/// Configuration for Swift Package Manager dependencies.
public struct Dependencies: Codable, Equatable {
    /// The path to the `Package.swift` manifest defining the dependencies. If not provided, `Tuist/Package.swift` is used.
    public let package: Path?

    /// The custom `Product` type to be used for SPM targets.
    public let productTypes: [String: Product]

    // The base settings to be used for targets generated from SwiftPackageManager.
    public let baseSettings: Settings

    // Additional settings to be added to targets generated from SwiftPackageManager.
    public let targetSettings: [String: SettingsDictionary]

    /// Custom project configurations to be used for projects generated from SwiftPackageManager.
    public let projectOptions: [String: ProjectDescription.Project.Options]

    /// Creates `Dependencies` instance using the package manifest at `Tuist/Package.swift`.
    /// - Parameter productTypes: The custom `Product` types to be used for SPM targets.
    /// - Parameter baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter projectOptions: Custom project configurations to be used for projects generated from SwiftPackageManager.
    public init(
        package: Path? = nil,
        productTypes: [String: Product] = [:],
        baseSettings: Settings = .settings(),
        targetSettings: [String: SettingsDictionary] = [:],
        projectOptions: [String: ProjectDescription.Project.Options] = [:]
    ) {
        self.package = package
        self.productTypes = productTypes
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
    }
}
