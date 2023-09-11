import Foundation
import TuistGraph

struct UnspecifiedPlatformError: Error, CustomStringConvertible {
    let target: Target
    var description: String {
        "Only single platform targets supported. The target \(target.name) specifies multiple supported platforms (\(target.supportedPlatforms.map(\.rawValue).joined(separator: ", ")))."
    }
}

extension Target {
    /// Platform for use with services when a platform is not specified
    var servicePlatform: Platform {
        get throws {
            guard destinations.platforms.count == 1,
                  let platform = destinations.first?.platform
            else {
                throw UnspecifiedPlatformError(target: self)
            }

            return platform
        }
    }
}
