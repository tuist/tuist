
public typealias PlatformFilters = Set<PlatformFilter>

public enum PlatformFilter: Comparable, Hashable, Codable {
    case ios
    case macos
    case tvos
    case catalyst
    case driverkit
    case watchos
    case visionos
}
