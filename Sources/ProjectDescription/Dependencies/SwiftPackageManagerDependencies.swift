import Foundation

/// Contains the description of a dependency that can be installed using Swift Package Manager.
public struct SwiftPackageManagerDependencies: Codable, Equatable {
    /// List of packages that will be installed using Swift Package Manager.
    public let packages: [Package]

    /// List of options for Swift Package Manager installation.
    public let options: Set<Options>

    /// Creates `SwiftPackageManagerDependencies` instance.
    /// - Parameter packages: List of packages that will be installed using Swift Package Manager.
    /// - Parameter options: List of options for Swift Package Manager installation.
    public static func swiftPackageManager(
        _ packages: [Package],
        options: Set<Options> = []
    ) -> Self {
        .init(
            packages: packages,
            options: options
        )
    }
}

// MARK: - SwiftPackageManagerDependencies.Options

public extension SwiftPackageManagerDependencies {
    /// The options that you can set for Swift Package Manager installation.
    enum Options: Codable, Equatable, Hashable {
        /// When passed, Tuist will add the specified tools version to the `Package.swift` manifest file.
        /// When not passed, the environment’s tools version will be used.
        case swiftToolsVersion(Version)
    }
}

// MARK: - SwiftPackageManagerDependencies.Options: Codable

extension SwiftPackageManagerDependencies.Options {
    private enum Kind: String, Codable {
        case swiftToolsVersion
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .swiftToolsVersion:
            let version = try container.decode(Version.self, forKey: .version)
            self = .swiftToolsVersion(version)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .swiftToolsVersion(version):
            try container.encode(Kind.swiftToolsVersion, forKey: .kind)
            try container.encode(version, forKey: .version)
        }
    }
}
