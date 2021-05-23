import Foundation

/// Contains the description of a dependency that can be installed using Swift Package Manager.
public struct SwiftPackageManagerDependencies: Equatable {
    /// List of packages that will be installed using Swift Package Manager.
    public let packages: [Package]

    /// List of options for Carthage installation.
    public let options: Set<Options>

    /// Initializes a new `SwiftPackageManagerDependencies` instance.
    /// - Parameters:
    ///    - packages: List of packages that will be installed using Swift Package Manager.
    ///    - options: List of options for Swift Package Manager installation.
    public init(
        _ packages: [Package],
        options: Set<Options>
    ) {
        self.packages = packages
        self.options = options
    }
}

extension SwiftPackageManagerDependencies {
    /// Returns the version of swift tools that should be used to resolve dependencies or `nil` when the version is unspecified.
    public var swiftToolsVersion: String? {
        options
            .compactMap { option -> String? in
                switch option {
                case let .swiftToolsVersion(version):
                    return version
                }
            }.first
    }

    /// Returns `Package.swift` representation.
    ///
    /// **NOTE** It is a temporary solution until Apple resolves: https://forums.swift.org/t/pitch-package-editor-commands/42224
    public func manifestValue() -> String {
        """
        import PackageDescription

        let package = Package(
            name: "PackageName",
            dependencies: [
                \(packages.map { $0.manifestValue + "," }.joined(separator: "\n\t"))
            ]
        )
        """
    }
}

// MARK: - SwiftPackageManagerDependencies.Options

public extension SwiftPackageManagerDependencies {
    /// The options that you can set for Swift Package Manager installation.
    enum Options: Equatable, Hashable {
        /// When passed, Tuist will add the specified tools version to the `Package.swift` manifest file.
        /// When not passed, the environment’s tools version will be used.
        case swiftToolsVersion(String)
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
