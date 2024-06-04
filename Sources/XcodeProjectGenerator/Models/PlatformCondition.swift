import Foundation
import TSCBasic

public struct PlatformCondition: Codable, Hashable, Equatable, Comparable {
    public static func < (lhs: PlatformCondition, rhs: PlatformCondition) -> Bool {
        lhs.platformFilters < rhs.platformFilters
    }

    public static func < (lhs: PlatformCondition, rhs: PlatformCondition?) -> Bool {
        guard let rhsFilters = rhs?.platformFilters else { return false }
        return lhs.platformFilters < rhsFilters
    }

    public let platformFilters: PlatformFilters
    private init(platformFilters: PlatformFilters) {
        self.platformFilters = platformFilters
    }

    public static func when(_ platformFilters: Set<PlatformFilter>) -> PlatformCondition? {
        guard !platformFilters.isEmpty else { return nil }
        return PlatformCondition(platformFilters: platformFilters)
    }

    public func intersection(_ other: PlatformCondition?) -> CombinationResult {
        guard let otherFilters = other?.platformFilters else { return .condition(self) }
        let filters = platformFilters.intersection(otherFilters)

        if filters.isEmpty {
            return .incompatible
        } else {
            return .condition(PlatformCondition(platformFilters: filters))
        }
    }

    public func union(_ other: PlatformCondition?) -> CombinationResult {
        guard let otherFilters = other?.platformFilters else { return .condition(nil) }
        let filters = platformFilters.union(otherFilters)

        if filters.isEmpty {
            return .condition(nil)
        } else {
            return .condition(PlatformCondition(platformFilters: filters))
        }
    }

    public enum CombinationResult: Equatable {
        case incompatible
        case condition(PlatformCondition?)

        public func combineWith(_ other: CombinationResult) -> CombinationResult {
            switch (self, other) {
            case (.incompatible, .incompatible):
                return .incompatible
            case (_, .incompatible):
                return self
            case (.incompatible, _):
                return other
            case let (.condition(lhs), .condition(rhs)):
                guard let lhs, let rhs else { return .condition(nil) }
                return lhs.union(rhs)
            }
        }
    }
}
