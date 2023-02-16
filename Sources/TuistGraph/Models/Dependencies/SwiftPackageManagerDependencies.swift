import Foundation
import TSCBasic

/// Contains the description of a dependency that can be installed using Swift Package Manager.
///
/// Example:
///
/// ```swift
/// let packageManager = SwiftPackageManagerDependencies(
///     packages: [
///         .package(url: "https://github.com/Alamofire/Alamofire", .upToNextMajor(from: "5.6.0")),
///         .local(path: "MySwiftPackage")
///     ],
///     baseSettings: .settings(configurations: [.debug(name: .debug), .release(name: .release)]),
///     targetSettings: ["MySwiftPackageTarget": ["IPHONEOS_DEPLOYMENT_TARGET": SettingValue.string("13.0")]],
///     projectOptions: ["MySwiftPackage":  .options(disableSynthesizedResourceAccessors: false)]
/// )
/// ```

public struct SwiftPackageManagerDependencies: Equatable {
    /// List of packages that will be installed using Swift Package Manager.
    public let packages: [Package]

    /// The custom `Product` types to be used for SPM targets.
    public let productTypes: [String: Product]

    // The base settings to be used for targets generated from SwiftPackageManager
    public let baseSettings: Settings

    /// The custom `Settings` to be applied to SPM targets
    public let targetSettings: [String: SettingsDictionary]

    /// The custom project options for each project generated from a swift package
    public let projectOptions: [String: TuistGraph.Project.Options]

    /// Initializes a new `SwiftPackageManagerDependencies` instance.
    /// - Parameters:
    ///    - packages: List of packages that will be installed using Swift Package Manager.
    ///    - productTypes: The custom `Product` types to be used for SPM targets.
    ///    - baseSettings: The base settings to be used for targets generated from SwiftPackageManager
    ///    - targetSettings: The custom `SettingsDictionary` to be applied to denoted targets
    ///    - projectOptions: The custom project options for each project generated from a swift package

    public init(
        _ packages: [Package],
        productTypes: [String: Product],
        baseSettings: Settings,
        targetSettings: [String: SettingsDictionary],
        projectOptions: [String: TuistGraph.Project.Options] = [:]
    ) {
        self.packages = packages
        self.productTypes = productTypes
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
    }
}

extension SwiftPackageManagerDependencies {
    /// Returns `Package.swift` representation.
    public func manifestValue(isLegacy: Bool, packageManifestFolder: AbsolutePath) -> String {
        """
        import PackageDescription

        let package = Package(
            name: "PackageName",
            dependencies: [
                \(packages.map {
                    let manifest = $0.manifestValue(isLegacy: isLegacy, packageManifestFolder: packageManifestFolder)
                    return manifest + ","
                }.joined(separator: "\n        "))
            ]
        )

        """
    }
}

// MARK: - Package.manifestValue()

extension Package {
    /// Returns `Package.swift` representation.
    fileprivate func manifestValue(isLegacy: Bool, packageManifestFolder: AbsolutePath) -> String {
        switch self {
        case let .local(path):
            return #".package(path: "\#(path.relative(to: packageManifestFolder))")"#
        case let .remote(url, requirement):
            let requirementManifestValue = isLegacy ? requirement.legacyManifestValue : requirement.manifestValue
            return #".package(url: "\#(url)", \#(requirementManifestValue))"#
        }
    }
}

// MARK: - Requirement.manifestValue()

extension Requirement {
    /// Returns `Package.swift` representation.
    fileprivate var manifestValue: String {
        switch self {
        case let .exact(version):
            return #"exact: "\#(version)""#
        case let .upToNextMajor(version):
            return #"from: "\#(version)""#
        case let .upToNextMinor(version):
            return #".upToNextMinor(from: "\#(version)")"#
        case let .branch(branch):
            return #"branch: "\#(branch)""#
        case let .revision(revision):
            return #"revision: "\#(revision)""#
        case let .range(from, to):
            return #""\#(from)" ..< "\#(to)""#
        }
    }

    /// Returns legacy `Package.swift` representation.
    fileprivate var legacyManifestValue: String {
        switch self {
        case let .exact(version):
            return #".exact("\#(version)")"#
        case let .upToNextMajor(version):
            return #".upToNextMajor(from: "\#(version)")"#
        case let .upToNextMinor(version):
            return #".upToNextMinor(from: "\#(version)")"#
        case let .branch(branch):
            return #".branch("\#(branch)")"#
        case let .revision(revision):
            return #".revision("\#(revision)")"#
        case let .range(from, to):
            return #""\#(from)" ..< "\#(to)""#
        }
    }
}
