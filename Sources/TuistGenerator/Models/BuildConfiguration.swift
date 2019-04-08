import Foundation

public struct BuildConfiguration {

    public enum Variant: String {
        case all, debug, release
    }

    public static let debug = BuildConfiguration(name: "Debug", predefined: true, variant: .debug)
    public static let release = BuildConfiguration(name: "Release", predefined: true, variant: .release)

    public let name: String
    public let variant: Variant

    let predefined: Bool

    public init(name: String, variant: Variant) {
        self.init(name: name, predefined: false, variant: variant)
    }

    init(name: String, predefined: Bool, variant: Variant) {
        self.name = name
        self.predefined = predefined
        self.variant = variant
    }
}

extension BuildConfiguration: Equatable {

    public static func ==(lhs: BuildConfiguration, rhs: BuildConfiguration) -> Bool {
        return lhs.predefined == rhs.predefined && lhs.name == rhs.name
    }
}

extension BuildConfiguration: Hashable {
}

extension BuildConfiguration: XcodeRepresentable {
    public var xcodeValue: String { return name }
}
