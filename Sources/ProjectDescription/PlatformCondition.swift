import Foundation

/// A condition applied to an "entity" allowing it to only be used in certain circumstances
public struct PlatformCondition: Codable, Hashable, Equatable {
    public let platformFilters: Set<PlatformFilter>
}
