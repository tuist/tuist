import TuistSupport

public struct TestIdentifier: CustomStringConvertible, Hashable {
    enum Error: FatalError {
        case invalidTestIdentifier(value: String)

        // Error description
        var description: String {
            switch self {
            case let .invalidTestIdentifier(value):
                return "Invalid test identifiers \(value). The expected format is TestTarget[/TestClass[/TestMethod]]."
            }
        }

        // Error type
        var type: ErrorType {
            switch self {
            case .invalidTestIdentifier:
                return .abort
            }
        }
    }

    public let target: String
    public let `class`: String?
    public let method: String?

    public var description: String {
        Self.description(target: target, class: `class`, method: method)
    }

    public init(target: String, class: String? = nil) throws {
        try self.init(
            target: target,
            class: `class`,
            method: nil
        )
    }

    public init(target: String, class: String?, method: String?) throws {
        if target.isEmpty || `class`.isEmptyButNotNil || method.isEmptyButNotNil {
            throw Error.invalidTestIdentifier(value: Self.description(target: target, class: `class`, method: method))
        }

        self.target = target
        self.class = `class`
        self.method = method
    }

    public init(string: String) throws {
        let testInfo = string.split(separator: "/", omittingEmptySubsequences: false)
        func getSafely(_ index: Int) -> String? {
            testInfo.indices.contains(index) ? String(testInfo[index]) : nil
        }

        guard let target = getSafely(0), testInfo.count <= 3 else {
            throw Error.invalidTestIdentifier(value: string)
        }
        try self.init(
            target: target,
            class: getSafely(1),
            method: getSafely(2)
        )
    }

    private static func description(target: String, class: String?, method: String?) -> String {
        var description = target
        if let `class` = `class` {
            description += "/\(`class`)"
        }
        if let method = method {
            description += "/\(method)"
        }
        return description
    }
}

extension Optional where Wrapped == String {
    fileprivate var isEmptyButNotNil: Bool {
        if let self = self, self.isEmpty {
            return true
        }
        return false
    }
}
