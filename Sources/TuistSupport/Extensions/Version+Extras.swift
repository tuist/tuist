import Foundation
import SPMUtility

extension Version {
    static func swiftVersion(_ value: String) -> Version {
        let components = value.split(separator: ".")
        let major = Int(String(components[0]))!
        let minor: Int
        let patch: Int

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
        return Version(major, minor, patch)
    }
}
