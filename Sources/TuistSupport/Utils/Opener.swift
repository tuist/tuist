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
    func open(url: URL) throws
    func open(target: String, wait: Bool) throws
}

public class Opener: Opening {
    public init() {}

    // MARK: - Opening

    public func open(path: AbsolutePath) throws {
        if !FileHandler.shared.exists(path) {
            throw OpeningError.notFound(path)
        }
        try open(target: path.pathString, wait: false)
    }

    public func open(url: URL) throws {
        try open(target: url.absoluteString, wait: false)
    }

    public func open(target: String, wait: Bool) throws {
        var arguments: [String] = []
        arguments.append(contentsOf: ["/usr/bin/open"])
        if wait { arguments.append("-W") }
        arguments.append(target)

        try System.shared.run(arguments)
    }
}
