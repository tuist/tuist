import Foundation

public enum SystemError: FatalError, Equatable {
    case terminated(command: String, code: Int32, standardError: Data)
    case signalled(command: String, code: Int32, standardError: Data)
    case parseSwiftVersion(String)

    public var description: String {
        switch self {
        case let .signalled(command, code, data):
            if data.count > 0, let string = String(data: data, encoding: .utf8) {
                return "The command `\(command)` was interrupted with a signal \(code) and message:\n\(string)"
            } else {
                return "The command `\(command)` was interrupted with a signal \(code)"
            }
        case let .terminated(command, code, data):
            if data.count > 0, let string = String(data: data, encoding: .utf8) {
                return "The command `\(command)` exited with error code \(code) and message:\n\(string)"
            } else {
                return "The command `\(command)` exited with error code \(code)"
            }
        case let .parseSwiftVersion(output):
            return "Couldn't obtain the Swift version from the output: \(output)."
        }
    }

    public var type: ErrorType {
        switch self {
        case .signalled: return .abort
        case .parseSwiftVersion: return .bug
        case .terminated: return .abort
        }
    }
}
