import Foundation

/// A collection of external dependencies.
///
///
/// ```swift
/// TODO: Update this
/// import ProjectDescription
///
/// let dependencies = Dependencies(
///     carthage: [
///         .github(path: "Alamofire/Alamofire", requirement: .exact("5.0.4")),
///     ],
///     swiftPackageManager: [
///         .remote(url: "https://github.com/Alamofire/Alamofire", requirement: / .upToNextMajor(from: "5.0.0")),
///     ],
///     platforms: [.iOS]
/// )
/// ```
public struct PackageSettings: Codable, Equatable {
    /// The custom `Product` type to be used for SPM targets.
    public var productTypes: [String: Product]

    // The base settings to be used for targets generated from SwiftPackageManager
    public var baseSettings: Settings

    // Additional settings to be added to targets generated from SwiftPackageManager.
    public var targetSettings: [String: SettingsDictionary]

    /// Custom project configurations to be used for projects generated from SwiftPackageManager.
    public var projectOptions: [String: ProjectDescription.Project.Options]
    
    /// The custom set of `platforms` that are used by your project
    public let platforms: Set<PackagePlatform>

    /// Creates `SwiftPackageManagerDependencies` instance using the package manifest at `Tuist/Package.swift`.
    /// - Parameter productTypes: The custom `Product` types to be used for SPM targets.
    /// - Parameter baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter projectOptions: Custom project configurations to be used for projects generated from SwiftPackageManager.
    /// - Parameter platforms: The custom set of `platforms` that are used by your project
    public init(
        productTypes: [String: Product] = [:],
        baseSettings: Settings = .settings(),
        targetSettings: [String: SettingsDictionary] = [:],
        projectOptions: [String: ProjectDescription.Project.Options] = [:],
        platforms: Set<PackagePlatform> = Set(PackagePlatform.allCases)
    ) {
        self.productTypes = productTypes
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
        self.platforms = platforms
        dumpIfNeeded(self)
    }
}
