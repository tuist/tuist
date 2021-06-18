import Foundation
import TSCBasic

// A enum containing information about third party dependency.
public enum ThirdPartyDependency: Hashable, Codable {
    /// A dependency that is imported as source code.
    case sources(name: String, products: [Product], targets: [Target], minDeploymentTargets: Set<DeploymentTarget>)

    /// A dependency that represents a pre-compiled .xcframework.
    case xcframework(name: String, path: AbsolutePath, architectures: Set<BinaryArchitecture>)
}

extension ThirdPartyDependency {
    /// The name of the third party dependency.
    public var name: String {
        switch self {
        case let .sources(name, _, _, _), let .xcframework(name, _, _):
            return name
        }
    }
}

extension ThirdPartyDependency {
    /// A product that can be imported from projects depending on this dependency.
    public struct Product: Codable, Hashable {
        /// The type of product.
        public enum LibraryType: String, Codable {
            /// Static library.
            case `static`

            /// Dynamic library.
            case dynamic

            /// The type of library is unspecified and should be decided at generation time.
            case automatic
        }

        /// The name of the product.
        public let name: String

        /// Tha targets belonging to the product.
        public let targets: [String]

        /// The type of product.
        public let libraryType: LibraryType

        public init(name: String, targets: [String], libraryType: LibraryType) {
            self.name = name
            self.targets = targets
            self.libraryType = libraryType
        }
    }
}

extension ThirdPartyDependency {
    public struct Target: Codable, Hashable {
        /// The name of the target.
        public let name: String

        /// The paths containing the target sources.
        public let sources: [AbsolutePath]

        /// The paths containing the target resources.
        public let resources: [AbsolutePath]

        /// The target dependencies.
        public let dependencies: [Dependency]

        /// The custom public headers path.
        public let publicHeadersPath: String?

        /// The header search paths for C code.
        public let cHeaderSearchPaths: [String]

        /// The header search paths for C++ code.
        public let cxxHeaderSearchPaths: [String]

        /// The compilation conditions to be defined for C code.
        public let cDefines: [String: String]

        /// The compilation conditions to be defined for C++ code.
        public let cxxDefines: [String: String]

        /// The compilation conditions to be definedfor Swift code.
        public let swiftDefines: [String: String]

        /// The additional build flags for C code.
        public let cFlags: [String]

        /// The additional build flags for C++ code.
        public let cxxFlags: [String]

        /// The additional build flags for Swift code.
        public let swiftFlags: [String]

        public init(
            name: String,
            sources: [AbsolutePath],
            resources: [AbsolutePath],
            dependencies: [Dependency],
            publicHeadersPath: String?,
            cHeaderSearchPaths: [String],
            cxxHeaderSearchPaths: [String],
            cDefines: [String: String],
            cxxDefines: [String: String],
            swiftDefines: [String: String],
            cFlags: [String],
            cxxFlags: [String],
            swiftFlags: [String]
        ) {
            self.name = name
            self.sources = sources
            self.resources = resources
            self.dependencies = dependencies
            self.publicHeadersPath = publicHeadersPath
            self.cHeaderSearchPaths = cHeaderSearchPaths
            self.cxxHeaderSearchPaths = cxxHeaderSearchPaths
            self.cDefines = cDefines
            self.cxxDefines = cxxDefines
            self.swiftDefines = swiftDefines
            self.cFlags = cFlags
            self.cxxFlags = cxxFlags
            self.swiftFlags = swiftFlags
        }
    }
}

extension ThirdPartyDependency.Target {
    public enum Dependency: Codable, Hashable {
        /// A linked framework dependency.
        case linkedFramework(name: String, platforms: Set<Platform>?)

        /// A linked library dependency.
        case linkedLibrary(name: String, platforms: Set<Platform>?)

        /// A target belonging to the dependency itself.
        case target(name: String, platforms: Set<Platform>?)

        /// A target belonging to another dependency.
        case thirdPartyTarget(dependency: String, product: String, platforms: Set<Platform>?)

        /// A binary dependency.
        case xcframework(path: AbsolutePath, platforms: Set<Platform>?)
    }
}

// MARK: - Codable

extension ThirdPartyDependency {
    private enum Kind: String, Codable {
        case sources
        case xcframework
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case products
        case targets
        case minDeploymentTargets
        case path
        case architectures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .sources:
            let name = try container.decode(String.self, forKey: .name)
            let products = try container.decode([Product].self, forKey: .products)
            let targets = try container.decode([Target].self, forKey: .targets)
            let minDeploymentTargets = try container.decode(Set<DeploymentTarget>.self, forKey: .minDeploymentTargets)
            self = .sources(name: name, products: products, targets: targets, minDeploymentTargets: minDeploymentTargets)
        case .xcframework:
            let name = try container.decode(String.self, forKey: .name)
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            let architectures = try container.decode(Set<BinaryArchitecture>.self, forKey: .architectures)
            self = .xcframework(name: name, path: path, architectures: architectures)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .sources(name, products, targets, minDeploymentTargets):
            try container.encode(Kind.sources, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(products, forKey: .products)
            try container.encode(targets, forKey: .targets)
            try container.encode(minDeploymentTargets, forKey: .minDeploymentTargets)
        case let .xcframework(name, path, architectures):
            try container.encode(Kind.xcframework, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
            try container.encode(architectures, forKey: .architectures)
        }
    }
}

extension ThirdPartyDependency.Target.Dependency {
    private enum Kind: String, Codable {
        case linkedFramework
        case linkedLibrary
        case target
        case thirdPartyTarget
        case xcframework
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case platforms
        case dependency
        case path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let platforms = try container.decode(Set<Platform>.self, forKey: .platforms)
        switch kind {
        case .linkedFramework:
            let name = try container.decode(String.self, forKey: .name)
            self = .linkedFramework(name: name, platforms: platforms)
        case .linkedLibrary:
            let name = try container.decode(String.self, forKey: .name)
            self = .linkedLibrary(name: name, platforms: platforms)
        case .target:
            let name = try container.decode(String.self, forKey: .name)
            self = .target(name: name, platforms: platforms)
        case .thirdPartyTarget:
            let dependency = try container.decode(String.self, forKey: .dependency)
            let product = try container.decode(String.self, forKey: .name)
            self = .thirdPartyTarget(dependency: dependency, product: product, platforms: platforms)
        case .xcframework:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .xcframework(path: path, platforms: platforms)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .linkedFramework(name, platforms):
            try container.encode(Kind.linkedFramework, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(platforms, forKey: .platforms)
        case let .linkedLibrary(name, platforms):
            try container.encode(Kind.linkedLibrary, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(platforms, forKey: .platforms)
        case let .target(name, platforms):
            try container.encode(Kind.target, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(platforms, forKey: .platforms)
        case let .thirdPartyTarget(dependency, product, platforms):
            try container.encode(Kind.thirdPartyTarget, forKey: .kind)
            try container.encode(dependency, forKey: .dependency)
            try container.encode(product, forKey: .name)
            try container.encode(platforms, forKey: .platforms)
        case let .xcframework(path, platforms):
            try container.encode(Kind.xcframework, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(platforms, forKey: .platforms)
        }
    }
}
