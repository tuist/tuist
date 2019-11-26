import Basic
import Foundation

enum OpeningError: FatalError, Equatable {
    case notFound(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .notFound:
            return .bug
        }
    }

    var description: String {
        switch self {
        case let .notFound(path):
            return "Couldn't open file at path \(path.pathString)"
        }
    }

    static func == (lhs: OpeningError, rhs: OpeningError) -> Bool {
        switch (lhs, rhs) {
        case let (.notFound(lhsPath), .notFound(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

public protocol Opening: AnyObject {
    func open(path: AbsolutePath) throws
    func open(path: AbsolutePath, wait: Bool) throws
}

public class Opener: Opening {
    public init() {}

    // MARK: - Opening

    public func open(path: AbsolutePath) throws {
        try open(path: path, wait: true)
    }

    public func open(path: AbsolutePath, wait: Bool) throws {
        if !FileHandler.shared.exists(path) {
            throw OpeningError.notFound(path)
        }
        var arguments: [String] = []
        arguments.append(contentsOf: ["/usr/bin/open"])
        if wait { arguments.append("-W") }
        arguments.append(path.pathString)

        try System.shared.run(arguments)
    }
}
