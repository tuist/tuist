import Foundation
import XcodeProj

class PBXGroupSorter {
    // The sorting implementation was taken from https://github.com/yonaskolb/XcodeGen/blob/d64cfff8a1ca01fd8f18cbb41f72230983c4a192/Sources/XcodeGenKit/PBXProjGenerator.swift
    // We require exactly the same sort which places groups over files while using the PBXGroup from Xcodeproj.
    func sort(with group: PBXGroup) {
        let children = group.children
            .sorted { (child1, child2) -> Bool in
                let sortOrder1 = child1.getSortOrder()
                let sortOrder2 = child2.getSortOrder()

                if sortOrder1 != sortOrder2 {
                    return sortOrder1 < sortOrder2
                } else {
                    if (child1.name, child1.path) != (child2.name, child2.path) {
                        return PBXFileElement.sortByNamePath(child1, child2)
                    } else {
                        return child1.context ?? "" < child2.context ?? ""
                    }
                }
            }

        group.children = children.filter { $0 != group }

        let childGroups = group.children.compactMap { $0 as? PBXGroup }
        childGroups.forEach(sort)
    }
}

extension PBXFileElement {
    public func getSortOrder() -> Int {
        if type(of: self).isa == "PBXGroup" {
            return -1
        } else {
            return 0
        }
    }

    public static func sortByNamePath(_ lhs: PBXFileElement, _ rhs: PBXFileElement) -> Bool {
        lhs.namePathSortString.localizedStandardCompare(rhs.namePathSortString) == .orderedAscending
    }

    private var namePathSortString: String {
        "\(name ?? path ?? "")\t\(name ?? "")\t\(path ?? "")"
    }
}
