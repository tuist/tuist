import TuistSupport

public struct TestIdentifier: CustomStringConvertible {
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
        var description = target
        if let `class` = `class` {
            description += "/\(`class`)"
        }
        if let method = method {
            description += "/\(method)"
        }
        return description
    }

    public init(target: String, `class`: String? = nil, method: String? = nil) {
        self.target = target
        self.`class` = `class`
        self.method = method
    }

    public init(string: String) throws {
        let testInfo = string.split(separator: "/")
        func getSafely(_ index: Int) -> String? {
            testInfo.indices.contains(index) ? String(testInfo[index]) : nil
        }

        guard let target = getSafely(0), testInfo.count <= 3 else {
            throw Error.invalidTestIdentifier(value: string)
        }
        self.target = target
        `class` = getSafely(1)
        method = getSafely(2)
    }
}
