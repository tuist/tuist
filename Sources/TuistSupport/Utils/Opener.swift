import Foundation
import Mockable
import Path

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

@Mockable
public protocol Opening: AnyObject {
    func open(path: AbsolutePath, wait: Bool, fresh: Bool) throws
    func open(path: AbsolutePath, fresh: Bool) throws
    func open(path: AbsolutePath, application: AbsolutePath, fresh: Bool) throws
    func open(path: AbsolutePath, application: AbsolutePath, wait: Bool, fresh: Bool) throws
    func open(url: URL, fresh: Bool) throws
    func open(target: String, wait: Bool, fresh: Bool) throws
}

public class Opener: Opening {
    public init() {}

    // MARK: - Opening

    public func open(path: AbsolutePath, wait: Bool, fresh: Bool = false) throws {
        if !FileHandler.shared.exists(path) {
            throw OpeningError.notFound(path)
        }
        try open(target: path.pathString, wait: wait, fresh: fresh)
    }

    public func open(path: AbsolutePath, fresh: Bool = false) throws {
        try open(path: path, wait: false, fresh: fresh)
    }

    public func open(url: URL, fresh: Bool = false) throws {
        try open(target: url.absoluteString, wait: false, fresh: fresh)
    }

    public func open(target: String, wait: Bool, fresh: Bool = false) throws {
        var arguments: [String] = []
        arguments.append(contentsOf: ["/usr/bin/open"])
        if wait { arguments.append("-W") }
        if fresh { arguments.append("-F") }
        arguments.append(target)

        try System.shared.run(arguments)
    }

    public func open(path: AbsolutePath, application: AbsolutePath, fresh: Bool = false) throws {
        try open(path: path, application: application, wait: true, fresh: fresh)
    }

    public func open(path: AbsolutePath, application: AbsolutePath, wait: Bool, fresh: Bool = false) throws {
        var arguments: [String] = []
        arguments.append(contentsOf: ["/usr/bin/open"])
        arguments.append(path.pathString)
        arguments.append(contentsOf: ["-a", application.pathString])
        if wait { arguments.append("-W") }
        if fresh { arguments.append("-F") }
        try System.shared.run(arguments)
    }
}
