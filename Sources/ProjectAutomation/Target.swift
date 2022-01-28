import Foundation

/// The structure defining the output schema of a target.
public struct Target: Codable, Equatable {
    /// The name of the target.
    public let name: String

    /// The product type the target produces.
    public let product: String

    /// List of file paths that are the target's sources.
    public let sources: [String]

    public init(
        name: String,
        product: String,
        sources: [String]
    ) {
        self.name = name
        self.product = product
        self.sources = sources
    }
}
