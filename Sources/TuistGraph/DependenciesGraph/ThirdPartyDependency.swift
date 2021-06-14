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
            case `dynamic`

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
        /// The paths containing the target sources.
        public let sources: [AbsolutePath]

        /// The paths containing the target resources.
        public let resources: [AbsolutePath]

        /// The target dependencies
        public let dependencies: [Dependency]

        // TODO: check and add any other information needed to compile the sources (e.g. build flags)
    }
}

extension ThirdPartyDependency.Target {
    public enum Dependency: Codable, Hashable {
        /// A target belonging to the dependency itself.
        case target(name: String)

        /// A target belonging to another dependency.
        case thirdPartyTarget(dependency: String, target: String)

        /// A binary dependency.
        case xcframework(path: AbsolutePath)
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
        case target
        case thirdPartyTarget
        case xcframework
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case dependency
        case target
        case path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .target:
            let name = try container.decode(String.self, forKey: .target)
            self = .target(name: name)
        case .thirdPartyTarget:
            let dependency = try container.decode(String.self, forKey: .dependency)
            let target = try container.decode(String.self, forKey: .target)
            self = .thirdPartyTarget(dependency: dependency, target: target)
        case .xcframework:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .xcframework(path: path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .target(name):
            try container.encode(Kind.target, forKey: .kind)
            try container.encode(name, forKey: .target)
        case let .thirdPartyTarget(dependency, target):
            try container.encode(Kind.thirdPartyTarget, forKey: .kind)
            try container.encode(dependency, forKey: .dependency)
            try container.encode(target, forKey: .target)
        case let .xcframework(path):
            try container.encode(Kind.xcframework, forKey: .kind)
            try container.encode(path, forKey: .path)
        }
    }
}
