import TSCBasic
import TuistCore
import TuistSupport

// MARK: - Cartfile Content Generator Error

enum CartfileContentGeneratorError: FatalError, Equatable {
    /// Thrown when `Requirement.range` has been used for `carthage`'s dependency.
    case rangeRequirementNotSupported(dependencyName: String, fromVersion: String, toVersion: String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .rangeRequirementNotSupported:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .rangeRequirementNotSupported(dependencyName, fromVersion, toVersion):
            return "\(dependencyName) in version between \(fromVersion) and \(toVersion) can not be installed. Carthage do not support versions range requirement in Cartfile."
        }
    }
}

// MARK: - Cartfile Content Generating Error

public protocol CartfileContentGenerating {
    /// Generates content for `Cartfile`.
    /// - Parameter dependencies: The dependencies whose will be installed.
    func cartfileContent(for dependencies: [CarthageDependency]) throws -> String
}

// MARK: - Cartfile Content Generator

public final class CartfileContentGenerator: CartfileContentGenerating {
    public init() { }
    
    public func cartfileContent(for dependencies: [CarthageDependency]) throws -> String {
        try dependencies
            .map { try $0.toString() }
            .joined(separator: "\n")
    }
}

private extension CarthageDependency {
    func toString() throws -> String {
        switch requirement {
        case let .exact(version):
            return #"github "\#(name)" == \#(version)"#
        case let .upToNextMajor(version):
            return #"github "\#(name)" ~> \#(version)"#
        case let .upToNextMinor(version):
            return #"github "\#(name)" ~> \#(version)"#
        case let .range(fromVersion, toVersion):
            throw CartfileContentGeneratorError.rangeRequirementNotSupported(dependencyName: name, fromVersion: fromVersion, toVersion: toVersion)
        case let .branch(branch):
            return #"github "\#(name)" "\#(branch)""#
        case let .revision(revision):
            return #"github "\#(name)" "\#(revision)""#
        }
    }
}
