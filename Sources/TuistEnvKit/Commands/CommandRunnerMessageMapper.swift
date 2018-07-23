import Foundation

/// The instance that conforms this protocol is responsible
/// for generating the messages that are printed by the command runner.
protocol CommandRunnerMessageMapping: AnyObject {
    /// It returns the message that should be printed for a given resolved version.
    ///
    /// - Parameter version: resolved version.
    /// - Returns: message that should be printed.
    func resolvedVersion(_ version: ResolvedVersion) -> String?
}

/// Command runner message mapper.
class CommandRunnerMessageMapper: CommandRunnerMessageMapping {
    /// It returns the message that should be printed for a given resolved version.
    ///
    /// - Parameter version: resolved version.
    /// - Returns: message that should be printed.
    func resolvedVersion(_ version: ResolvedVersion) -> String? {
        switch version {
        case let .bin(path):
            return "Using bundled version at path \(path.asString)"
        case let .versionFile(path, value):
            return "Using version \(value) defined at \(path.asString)"
        case .undefined:
            return nil
        }
    }
}
