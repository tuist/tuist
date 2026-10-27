import XcodeGraph
import XcodeProj

/// A mapper for platform-related conditions, extracting platform filters from `PBXTargetDependency`.
extension PBXTargetDependency {
    /// Maps the platform filters on a given `PBXTargetDependency` into a `PlatformCondition`.
    ///
    /// Returns `nil` if no filters apply, meaning the dependency isn't restricted by platform and
    /// should be considered available on all platforms.
    func platformCondition() -> PlatformCondition? {
        var filters = Set(platformFilters ?? [])
        if let singleFilter = platformFilter {
            filters.insert(singleFilter)
        }

        let platformFilters = Set(filters.compactMap { PlatformFilter(rawValue: $0) })
        return PlatformCondition.when(platformFilters)
    }
}
