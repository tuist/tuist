import Foundation
import TuistLogging
import TuistSupport
import XcodeGraph

public struct UnspecifiedPlatformError: FatalError, CustomStringConvertible {
    public var type: ErrorType = .abort

    public let target: Target
    public var description: String {
        "Only single platform targets supported. The target \(target.name) specifies multiple supported platforms (\(target.supportedPlatforms.map(\.rawValue).joined(separator: ", ")))."
    }
}

extension Target {
    /// Platform for use with services when a platform is not specified
    public var servicePlatform: Platform {
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
