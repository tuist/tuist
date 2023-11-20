import Foundation
import TSCBasic

public enum PackagesOrManifest: Equatable {
    case packages([Package])
    case manifest(AbsolutePath)
}

/// Contains the description of a dependency that can be installed using Swift Package Manager.
public struct SwiftPackageManagerDependencies: Equatable {
    /// The path to the `Package.swift` manifest defining the dependencies, or the list of packages that will be installed using
    /// Swift Package Manager.
    public let packagesOrManifest: PackagesOrManifest

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
    ///    - packagesOrManifest: The path to the `Package.swift` manifest defining the dependencies, or the list of packages
    /// that will be installed using Swift Package Manager.
    ///    - productTypes: The custom `Product` types to be used for SPM targets.
    ///    - baseSettings: The base settings to be used for targets generated from SwiftPackageManager
    ///    - targetSettings: The custom `SettingsDictionary` to be applied to denoted targets
    ///    - projectOptions: The custom project options for each project generated from a swift package

    public init(
        _ packagesOrManifest: PackagesOrManifest,
        productTypes: [String: Product],
        baseSettings: Settings,
        targetSettings: [String: SettingsDictionary],
        projectOptions: [String: TuistGraph.Project.Options] = [:]
    ) {
        self.packagesOrManifest = packagesOrManifest
        self.productTypes = productTypes
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
    }
}

extension SwiftPackageManagerDependencies {
    public enum Manifest: Equatable {
        case content(String)
        case manifest
    }

    /// Returns `Package.swift` representation.
    public func manifest(isLegacy: Bool, packageManifestFolder: AbsolutePath) -> Manifest {
        switch packagesOrManifest {
        case let .packages(packages):
            return .content(
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
            )
        case .manifest:
            return .manifest
        }
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
