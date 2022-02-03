import Foundation
import TSCBasic

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
}

public protocol Opening: AnyObject {
    func open(path: AbsolutePath, wait: Bool) throws
    func open(path: AbsolutePath) throws
    func open(path: AbsolutePath, application: AbsolutePath) throws
    func open(path: AbsolutePath, application: AbsolutePath, wait: Bool) throws
    func open(url: URL) throws
    func open(target: String, wait: Bool) throws
}

public class Opener: Opening {
    public init() {}

    // MARK: - Opening

    public func open(path: AbsolutePath, wait: Bool) throws {
        if !FileHandler.shared.exists(path) {
            throw OpeningError.notFound(path)
        }
        try open(target: path.pathString, wait: wait)
    }

    public func open(path: AbsolutePath) throws {
        try open(path: path, wait: false)
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

    public func open(path: AbsolutePath, application: AbsolutePath) throws {
        try open(path: path, application: application, wait: true)
    }

    public func open(path: AbsolutePath, application: AbsolutePath, wait: Bool) throws {
        var arguments: [String] = []
        arguments.append(contentsOf: ["/usr/bin/open"])
        arguments.append(path.pathString)
        arguments.append(contentsOf: ["-a", application.pathString])
        if wait { arguments.append("-W") }
        try System.shared.run(arguments)
    }
}
