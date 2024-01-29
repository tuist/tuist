import Foundation
import TSCBasic

public struct GraphTargetReference: Equatable, Comparable, Hashable, CustomDebugStringConvertible, CustomStringConvertible,
    Codable
{
    /// Path to the directory that contains the project where the target is defined.
    public let graphTarget: GraphTarget

    public var target: Target { graphTarget.target }

    /// Platforms the target is conditionally deployed to.
    public let condition: PlatformCondition?

    public init(target: GraphTarget, condition: PlatformCondition? = nil) {
        graphTarget = target
        self.condition = condition
    }

    public static func < (lhs: GraphTargetReference, rhs: GraphTargetReference) -> Bool {
        lhs.graphTarget < rhs.graphTarget
//        guard let
//        return (lhs.condition, lhs.graphTarget) < (rhs.condtion, rhs.graphTarget)
//
//
//        switch (lhs.condition, rhs.condition) {
//        case (let lhsCondtion, let rhsCondtion):
//            return (lhsCondition, lhs.graphTarget) < (rhsCondtion, rhs.graphTarget)
//        case
//        }
    }

    // MARK: - CustomDebugStringConvertible/CustomStringConvertible

    public var debugDescription: String {
        description
    }

    public var description: String {
        "Target '\(target.name)' at path '\(graphTarget.project.path)'"
    }
}

//
// extension GraphTarget {
//    public func reference(_ condition: PlatformCondition?) -> GraphTargetReference {
//        return GraphTargetReference(target: self, condition: condition)
//    }
// }
