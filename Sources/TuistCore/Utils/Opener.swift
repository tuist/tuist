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
            return "Couldn't open file at path \(path.asString)"
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
}

public class Opener: Opening {
    // MARK: - Attributes

    private let system: Systeming
    private let fileHandler: FileHandling

    // MARK: - Init

    public init(system: Systeming = System(),
                fileHandler: FileHandling = FileHandler()) {
        self.system = system
        self.fileHandler = fileHandler
    }

    // MARK: - Opening

    public func open(path: AbsolutePath) throws {
        if !fileHandler.exists(path) {
            throw OpeningError.notFound(path)
        }
        try system.popen("open", path.asString, verbose: true)
    }
}
