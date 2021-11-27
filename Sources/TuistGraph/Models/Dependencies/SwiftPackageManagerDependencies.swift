import Foundation

/// Contains the description of a dependency that can be installed using Swift Package Manager.
public struct SwiftPackageManagerDependencies: Equatable {
    /// List of packages that will be installed using Swift Package Manager.
    public let packages: [Package]

    /// The custom `Product` types to be used for SPM targets.
    public let productTypes: [String: Product]

    // The base settings to be used for targets generated from SwiftPackageManager
    public let baseSettings: Settings

    /// The custom `Settings` to be applied to SPM targets
    public let targetSettings: [String: SettingsDictionary]

    /// Initializes a new `SwiftPackageManagerDependencies` instance.
    /// - Parameters:
    ///    - packages: List of packages that will be installed using Swift Package Manager.
    ///    - productTypes: The custom `Product` types to be used for SPM targets.
    ///    - baseSettings: The base settings to be used for targets generated from SwiftPackageManager
    ///    - targetSettings: The custom `SettingsDictionary` to be applied to denoted targets
    public init(
        _ packages: [Package],
        productTypes: [String: Product],
        baseSettings: Settings,
        targetSettings: [String: SettingsDictionary]
    ) {
        self.packages = packages
        self.productTypes = productTypes
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
    }
}

extension SwiftPackageManagerDependencies {
    /// Returns `Package.swift` representation.
    ///
    /// **NOTE** It is a temporary solution until Apple resolves: https://forums.swift.org/t/pitch-package-editor-commands/42224
    public func manifestValue() -> String {
        """
        import PackageDescription

        let package = Package(
            name: "PackageName",
            dependencies: [
                \(packages.map { $0.manifestValue + "," }.joined(separator: "\n        "))
            ]
        )
        """
    }
}

// MARK: - Package.manifestValue()

private extension Package {
    /// Returns `Package.swift` representation.
    var manifestValue: String {
        switch self {
        case let .local(path):
            return #".package(path: "\#(path)")"#
        case let .remote(url, requirement):
            return #".package(url: "\#(url)", \#(requirement.manifestValue))"#
        }
    }
}

// MARK: - Requirement.manifestValue()

private extension Requirement {
    /// Returns `Package.swift` representation.
    var manifestValue: String {
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
            return #""\#(from)"..<"\#(to)""#
        }
    }
}
