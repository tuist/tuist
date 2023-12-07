import Foundation

/// A condition applied to an "entity" allowing it to only be used in certain circumstances
public struct PlatformCondition: Codable, Hashable, Equatable {
    public let platformFilters: Set<PlatformFilter>
    /// For internal use only. use `.when` to ensure we can not have a `PlatformCondition` with an empty set of filters.
    private init(platformFilters: Set<PlatformFilter>) {
        self.platformFilters = platformFilters
    }

    /// Creates a condition using the specified set of filters.
    /// - Parameter platformFilters: filters to define which platforms this condition supports
    /// - Returns: a `Condition` with the given set of filters or `nil` if empty.
    public static func when(_ platformFilters: Set<PlatformFilter>) -> PlatformCondition? {
        guard !platformFilters.isEmpty else { return nil }
        return PlatformCondition(platformFilters: platformFilters)
    }
}
