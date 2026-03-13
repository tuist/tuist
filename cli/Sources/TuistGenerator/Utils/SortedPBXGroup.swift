import Foundation
import XcodeProj

@propertyWrapper
class SortedPBXGroup {
    var value: PBXGroup

    var wrappedValue: PBXGroup {
        get {
            value.childGroups.forEach(sort) // We preserve the order of the root level groups and files
            return value
        }
        set {
            value = newValue
        }
    }

    init(wrappedValue: PBXGroup) {
        value = wrappedValue
    }

    private func sort(with group: PBXGroup) {
        group.children.sort { child1, child2 -> Bool in
            PBXFileElement.sortByNameThenPath(child1, child2)
        }
        group.childGroups.forEach(sort)
    }
}

extension PBXGroup {
    fileprivate var childGroups: [PBXGroup] {
        children.compactMap { $0 as? PBXGroup }
    }
}

extension PBXFileElement {
    fileprivate static func sortByNameThenPath(_ lhs: PBXFileElement, _ rhs: PBXFileElement) -> Bool {
        lhs.namePathSortString.localizedStandardCompare(rhs.namePathSortString) == .orderedAscending
    }

    private var namePathSortString: String {
        "\(name ?? path ?? "")\t\(name ?? "")\t\(path ?? "")"
    }
}
