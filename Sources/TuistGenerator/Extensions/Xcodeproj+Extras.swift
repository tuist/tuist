import Foundation
import XcodeProj

public extension PBXFileElement {
    var nameOrPath: String {
        name ?? path ?? ""
    }
}

public extension PBXFileElement {
    /// File elements sort
    ///
    /// - Sorts elements in ascending order
    /// - Files precede Groups
    static func filesBeforeGroupsSort(lhs: PBXFileElement, rhs: PBXFileElement) -> Bool {
        switch (lhs, rhs) {
        case (is PBXGroup, is PBXGroup):
            return lhs.nameOrPath < rhs.nameOrPath
        case (is PBXGroup, _):
            return false
        case (_, is PBXGroup):
            return true
        default:
            return lhs.nameOrPath < rhs.nameOrPath
        }
    }
}
