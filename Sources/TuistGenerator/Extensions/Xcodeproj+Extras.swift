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
        let dependingTargetPlatformFilters = target.dependencyPlatformFilters

        if dependingTargetPlatformFilters.isDisjoint(with: filters) {
            // if no platforms in common, apply all filters to exclude from target
            applyPlatformFilters(filters)
        } else {
            let applicableFilters = dependingTargetPlatformFilters.intersection(filters)

            // Only apply filters if our intersection is a subset of the targets platforms
            if applicableFilters.isStrictSubset(of: dependingTargetPlatformFilters) {
                applyPlatformFilters(applicableFilters)
            }
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
