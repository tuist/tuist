import Foundation

/// A directed edge linking representing a dependent relationship
/// e.g. `from` (MainApp) depends on `to` (UIKit)
public struct GraphEdge: Hashable, Codable {
    public let from: GraphDependency
    public let to: GraphDependency
    public init(from: GraphDependency, to: GraphDependency) {
        self.from = from
        self.to = to
    }

    public init(from: GraphDependency, to: GraphTarget) {
        self.from = from
        self.to = .target(name: to.target.name, path: to.path)
    }
}
