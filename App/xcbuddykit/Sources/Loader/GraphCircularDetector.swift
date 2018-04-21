import Basic
import Foundation

/// Struct that represents a target, containing its name and the path to the folder where the Project.swift which defines the target is.
struct GraphCircularDetectorNode: Hashable {
    /// Path to the folder which contains the Project.swift that defines the target.
    let path: AbsolutePath

    /// Target name.
    let name: String
}

/// Protocol that defines a graph circular dependencies detection.
protocol GraphCircularDetecting: AnyObject {
    /// Method that should be called a given dependency starts being parsed.
    ///
    /// - Parameters:
    ///   - from: the dependency source target.
    ///   - to: the dependency target that is going to be parsed.
    /// - Throws: an error if a circular dependency is found.
    func start(from: GraphCircularDetectorNode, to: GraphCircularDetectorNode) throws

    /// Method that should be called when we've finished parsing a target.
    ///
    /// - Parameter node: target that we finished parsing.
    func complete(_ node: GraphCircularDetectorNode)
}

/// Circular dependencies detector.
final class GraphCircularDetector: GraphCircularDetecting {
    var edges: [GraphCircularDetectorNode: [GraphCircularDetectorNode]] = [:]

    /// Method that should be called a given dependency starts being parsed.
    ///
    /// - Parameters:
    ///   - from: the dependency source target.
    ///   - to: the dependency target that is going to be parsed.
    /// - Throws: an error if a circular dependency is found.
    func start(from: GraphCircularDetectorNode, to: GraphCircularDetectorNode) throws {
        if edges[to] != nil {
            throw GraphLoadingError.circularDependency(from, to)
        } else {
            var nodes = edges[from]
            if nodes == nil { nodes = [] }
            nodes?.append(to)
            edges[from] = nodes
        }
    }

    /// Method that should be called when we've finished parsing a target.
    ///
    /// - Parameter node: target that we finished parsing.
    func complete(_ node: GraphCircularDetectorNode) {
        let nodes = edges[node]
        edges.removeValue(forKey: node)
        nodes?.forEach({ complete($0) })
    }
}
