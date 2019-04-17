import Foundation

public struct BuildConfiguration {
    public enum Variant: String {
        case debug, release
    }

    public static let debug = BuildConfiguration(name: "Debug", variant: .debug)
    public static let release = BuildConfiguration(name: "Release", variant: .release)

    public let name: String
    public let variant: Variant

    public init(name: String, variant: Variant) {
        self.name = name
        self.variant = variant
    }

    public static func release(_ name: String) -> BuildConfiguration {
        return BuildConfiguration(name: name, variant: .release)
    }

    public static func debug(_ name: String) -> BuildConfiguration {
        return BuildConfiguration(name: name, variant: .debug)
    }
}

extension BuildConfiguration: Equatable {
    public static func == (lhs: BuildConfiguration, rhs: BuildConfiguration) -> Bool {
        return lhs.name.caseInsensitiveCompare(rhs.name) == .orderedSame && lhs.variant == rhs.variant
    }
}

extension BuildConfiguration: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name.lowercased())
        hasher.combine(variant)
    }
}

extension BuildConfiguration: XcodeRepresentable {
    public var xcodeValue: String { return name }
}
