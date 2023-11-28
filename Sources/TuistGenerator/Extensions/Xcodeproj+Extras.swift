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
    /// With Xcode 15, we're seeing `platformFilter` not have the effects we expect
    public func applyCondition(_ condition: TargetDependency.Condition?, applicableTo target: Target) {
        guard let filters = condition?.platformFilters else { return }
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
    public func applyPlatformFilters(_ filters: PlatformFilters?) {
        // Xcode expects no filters to be set if a `PBXBuildFile` applies to all platforms
        guard let filters, !filters.isEmpty else { return }

        if filters.count == 1,
           let filter = filters.first,
           useSinglePlatformFilter(for: filter)
        {
            platformFilter = filter.xcodeprojValue
        } else {
            platformFilters = filters.xcodeprojValue
        }
    }

    private func useSinglePlatformFilter(
        for platformFilter: PlatformFilter
    ) -> Bool {
        // Xcode uses the singlular `platformFilter` for a subset of filters
        // when specified as a single filter, however foew newer platform filters
        // uses the plural `platformFilters` even when specifying a single filter.
        switch platformFilter {
        case .catalyst, .ios:
            return true
        case .macos, .driverkit, .watchos, .tvos, .visionos:
            return false
        }
    }
}
