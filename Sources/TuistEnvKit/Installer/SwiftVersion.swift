import Foundation

struct SwiftVersion: Comparable, Equatable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ value: String) {
        let components = value.split(separator: ".")
        major = Int(String(components[0]))!

        if components.count == 3 {
            minor = Int(String(components[1]))!
            patch = Int(String(components[2]))!
        } else if components.count == 2 {
            minor = Int(String(components[1]))!
            patch = 0
        } else {
            minor = 0
            patch = 0
        }
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    // MARK: - Comparable

    static func < (lhs: SwiftVersion, rhs: SwiftVersion) -> Bool {
        lhs.major < rhs.major || lhs.minor < rhs.minor || lhs.patch < lhs.patch
    }
}
