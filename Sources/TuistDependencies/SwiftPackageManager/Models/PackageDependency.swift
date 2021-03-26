import Foundation

/// A model that represents a node in the Swift Package Manager resolved dependency graph.
public struct PackageDependency: Equatable, Codable {
    public let name: String
    public let url: String
    public let version: String
    public let path: String
    public let dependencies: [PackageDependency]
}
