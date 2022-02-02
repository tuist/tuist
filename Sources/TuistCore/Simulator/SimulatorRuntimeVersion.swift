import Foundation

public struct SimulatorRuntimeVersion: CustomStringConvertible, Hashable, ExpressibleByStringLiteral, Comparable, Decodable {
    // MARK: - Attributes

    public let major: Int
    public let minor: Int?
    public let patch: Int?

    // MARK: - Constructors

    init(major: Int, minor: Int? = nil, patch: Int? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(stringLiteral: try container.decode(String.self))
    }

    // MARK: - Internal

    func flattened() -> SimulatorRuntimeVersion {
        SimulatorRuntimeVersion(
            major: major,
            minor: minor ?? 0,
            patch: patch ?? 0
        )
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        var version = "\(major)"
        if let minor = minor {
            version.append(".\(minor)")
        } else {
            return version
        }
        if let patch = patch {
            version.append(".\(patch)")
        } else {
            return version
        }
        return version
    }

    // MARK: - Comparable

    public static func < (lhs: SimulatorRuntimeVersion, rhs: SimulatorRuntimeVersion) -> Bool {
        let lhs = lhs.flattened()
        let rhs = rhs.flattened()

        if lhs.major < rhs.major {
            return true
        } else if lhs.major == rhs.major {
            if lhs.minor! < rhs.minor! {
                return true
            } else if lhs.minor! == rhs.minor! {
                return lhs.patch! < rhs.patch!
            } else {
                return false
            }
        } else {
            return false
        }
    }

    // MARK: - ExpressibleByStringLiteral

    public init(stringLiteral value: String) {
        let components = value.split(separator: ".")

        // Major
        if let major = Int(String(components.first!)) {
            self.major = major
        } else {
            fatalError("Invalid major component. It should be an integer")
        }

        // Minor
        if components.count >= 2 {
            if let minor = Int(components[1]) {
                self.minor = minor
            } else {
                fatalError("Invalid minor component. It should be an integer")
            }
        } else {
            minor = nil
        }

        // Patch
        if components.count >= 3 {
            if let patch = Int(components[2]) {
                self.patch = patch
            } else {
                fatalError("Invalid patch component. It should be an integer")
            }
        } else {
            patch = nil
        }
    }
}
