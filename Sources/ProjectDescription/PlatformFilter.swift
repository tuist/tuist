public typealias PlatformFilters = Set<PlatformFilter>

extension PlatformFilters {
    public static let all = Set(PlatformFilter.allCases)
}

public enum PlatformFilter: Comparable, Hashable, Codable, CaseIterable {
    case ios
    case macos
    case tvos
    case catalyst
    case driverkit
    case watchos
    case visionos
}
