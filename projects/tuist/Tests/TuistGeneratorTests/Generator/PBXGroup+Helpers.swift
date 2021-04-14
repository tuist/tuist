import Foundation
import XcodeProj

extension PBXGroup {
    /// Returns all the child paths (recursively)
    ///
    /// e.g.
    ///    A
    ///    - B
    ///    - C
    ///    -- D
    /// Would return:
    ///         ["A/B", "A/C/D"]
    var flattenedChildren: [String] {
        children.flatMap { (element: PBXFileElement) -> [String] in
            switch element {
            case let group as PBXGroup:
                return group.flattenedChildren.map { group.nameOrPath + "/" + $0 }
            default:
                return [element.nameOrPath]
            }
        }
    }
}
