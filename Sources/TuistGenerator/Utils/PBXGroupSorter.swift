import Foundation
import XcodeProj

class PBXGroupSorter {
    // The sorting implementation was taken from https://github.com/yonaskolb/XcodeGen/blob/d64cfff8a1ca01fd8f18cbb41f72230983c4a192/Sources/XcodeGenKit/PBXProjGenerator.swift
    // We require exactly the same sort which places groups over files while using the PBXGroup from Xcodeproj.
    func sort(with group: PBXGroup) {
        group.children.sort { (child1, child2) -> Bool in
            let sortOrder1 = child1.getSortOrder()
            let sortOrder2 = child2.getSortOrder()
            if sortOrder1 != sortOrder2 {
                return sortOrder1 < sortOrder2
            } else {
                return PBXFileElement.sortByNameThenPath(child1, child2)
            }
        }
        group.children.compactMap { $0 as? PBXGroup }.forEach(sort)
    }
}

private extension PBXFileElement {
    func getSortOrder() -> Int {
        switch self {
        case is PBXGroup:
            return -1
        default:
            return 0
        }
    }

    static func sortByNameThenPath(_ lhs: PBXFileElement, _ rhs: PBXFileElement) -> Bool {
        return lhs.namePathSortString.localizedStandardCompare(rhs.namePathSortString) == .orderedAscending
    }

    var namePathSortString: String {
        "\(name ?? path ?? "")\t\(name ?? "")\t\(path ?? "")"
    }
}
