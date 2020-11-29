import TSCBasic
import TuistCore
import TuistSupport

// MARK: - Cartfile Content Generating Error

enum CartfileContentGeneratorError: FatalError, Equatable {
    /// Thrown when at least one of the dependencies is invalid.
    case invalidDependencies(validationErrors: [String])

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidDependencies:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .invalidDependencies(validationErrors):
            return "Cartfile can not be generated:\n" + validationErrors.map(\.description).joined(separator: "\n")
        }
    }
}

// MARK: - Cartfile Content Generating

public protocol CartfileContentGenerating {
    /// Generates content for `Cartfile`.
    /// - Parameter dependencies: The dependencies whose will be installed.
    func cartfileContent(for dependencies: [CarthageDependency]) throws -> String
}

// MARK: - Cartfile Content Generator

public final class CartfileContentGenerator: CartfileContentGenerating {
    public init() {}

    public func cartfileContent(for dependencies: [CarthageDependency]) throws -> String {
        try validate(dependencies: dependencies)

        return try dependencies
            .map { try $0.cartfileValue() }
            .joined(separator: "\n")
    }

    // MARK: - Helpers

    private func validate(dependencies: [CarthageDependency]) throws {
        let validationErrors = dependencies
            .reduce(into: [String]()) { result, dependency in
                switch dependency.requirement {
                case let .range(fromVersion, toVersion):
                    result.append("\(dependency.name) in version between \(fromVersion) and \(toVersion) can not be installed. Carthage do not support versions range requirement in Cartfile.")
                default:
                    break
                }
            }

        if !validationErrors.isEmpty {
            throw CartfileContentGeneratorError.invalidDependencies(validationErrors: validationErrors)
        }
    }
}
