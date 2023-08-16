import Foundation
import TuistGraph
import XcodeProj

extension PBXFileElement {
    public var nameOrPath: String {
        name ?? path ?? ""
    }
}

extension PBXFileElement {
    /// File elements sort
    ///
    /// - Sorts elements in ascending order
    /// - Files precede Groups
    public static func filesBeforeGroupsSort(lhs: PBXFileElement, rhs: PBXFileElement) -> Bool {
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

extension PBXBuildFile {
    /// Apply platform filters either `platformFilter` or `platformFilters` depending on count
    public func applyPlatformFilters(_ filters: PlatformFilters, applicableTo target: Target) {
        // If the dependency fewer platforms, apply filters.
        let dependingTargetPlatformFilters = target.dependencyPlatformFilters
        if filters.isSubset(of: dependingTargetPlatformFilters) {
            let applicableFilters = dependingTargetPlatformFilters.intersection(filters)
            applyPlatformFilters(applicableFilters)
        }
    }

    /// Apply platform filters either `platformFilter` or `platformFilters` depending on count
    public func applyPlatformFilters(_ filters: PlatformFilters) {
        guard !filters.isEmpty else { return }

        if filters.count == 1, let filter = filters.first {
            platformFilter = filter.xcodeprojValue
        } else {
            platformFilters = filters.xcodeprojValue
        }
    }
}
