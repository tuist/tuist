import TSCBasic
import TuistCore
import TuistSupport

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
            .map { try $0.cartfileValue() }
            .joined(separator: "\n")
    }
}
