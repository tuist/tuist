import Foundation

/// The structure defining the output schema of an target.
public struct TargetOutput: Codable, Equatable {
    /// The name of the target.
    public let name: String

    /// The product type the target produces.
    public let product: String

    public init(name: String, product: String) {
        self.name = name
        self.product = product
    }
}
