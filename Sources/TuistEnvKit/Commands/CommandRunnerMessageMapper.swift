import Foundation

protocol CommandRunnerMessageMapping: AnyObject {
    func resolvedVersion(_ version: ResolvedVersion) -> String?
}

/// Command runner message mapper.
class CommandRunnerMessageMapper: CommandRunnerMessageMapping {
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
