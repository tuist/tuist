import Foundation
import TSCBasic
import TuistSupport

/// A `Plugin` used to extend Tuist.
public enum Plugin: Equatable, Hashable {
    /// A type of plugin used to extend `ProjectDescription`.
    case helpers(name: String)
}

extension Plugin: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .helpers(name):
            return "\(name) helpers"
        }
    }
}
