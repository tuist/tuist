import Foundation

// MARK: - Carthage Dependency

/// Contains the descriptions of a dependencies to be fetched with Carthage.
public struct CarthageDependencies: Equatable {
    public let dependencies: [Dependency]
    public let options: Options
    
    /// Initializes the carthage dependency with its attributes.
    public init(dependencies: [Dependency], options: Options) {
        self.dependencies = dependencies
        self.options = options
    }

    /// Returns `Cartfile` representation.
    public var cartfileValue: String {
        dependencies
            .map(\.cartfileValue)
            .joined(separator: "\n")
    }
}

public extension CarthageDependencies {
    enum Dependency: Equatable {
        case github(path: String, requirement: Requirement)
        case git(path: String, requirement: Requirement)
        case binary(path: String, requirement: Requirement)

        /// Returns `Cartfile` representation.
        public var cartfileValue: String {
            switch self {
            case let .github(path, requirement):
                return #"github "\#(path)" \#(requirement.cartfileValue)"#
            case let .git(path, requirement):
                return #"git "\#(path)" \#(requirement.cartfileValue)"#
            case let .binary(path, requirement):
                return #"binary "\#(path)" \#(requirement.cartfileValue)"#
            }
        }
    }
    
    enum Requirement: Equatable {
        case exact(String)
        case upToNext(String)
        case atLeast(String)
        case branch(String)
        case revision(String)

        /// Returns `Cartfile` representation.
        public var cartfileValue: String {
            switch self {
            case let .exact(version):
                return "== \(version)"
            case let .upToNext(version):
                return "~> \(version)"
            case let .atLeast(version):
                return ">= \(version)"
            case let .branch(branch):
                return #""\#(branch)""#
            case let .revision(revision):
                return #""\#(revision)""#
            }
        }
    }
    
    struct Options: Equatable {
        public let platforms: Set<Platform>
        public let useXCFrameworks: Bool
        
        public init(platforms: Set<Platform>, useXCFrameworks: Bool) {
            self.platforms = platforms
            self.useXCFrameworks = useXCFrameworks
        }
    }
}
