import TuistConfig
import TuistLogging
import TuistSupport

public struct TestIdentifier: CustomStringConvertible, Hashable {
    enum Error: FatalError {
        case invalidTestIdentifier(value: String)
        case targetTagsUnavailable

        // Error description

        var description: String {
            switch self {
            case let .invalidTestIdentifier(value):
                return "Invalid test identifiers \(value). The expected format is TestTarget[/TestClass[/TestMethod]]."
            case .targetTagsUnavailable:
                return "The test products do not contain target tags. Rebuild them with this version of Tuist to filter tests by tag."
            }
        }

        // Error type

        var type: ErrorType {
            switch self {
            case .invalidTestIdentifier, .targetTagsUnavailable:
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

    /// Expands a target tag query while preserving any suite or test method filter.
    /// Named identifiers are unchanged, including when reading legacy test products without tags.
    public func resolvingTargetQuery(targetTags: [String: Set<String>]?) throws -> [TestIdentifier] {
        guard case let .tagged(tag) = TargetQuery(stringLiteral: target) else {
            return [self]
        }
        guard let targetTags else {
            throw Error.targetTagsUnavailable
        }
        return try targetTags.keys.sorted().compactMap { name in
            guard targetTags[name]?.contains(tag) == true else { return nil }
            return try TestIdentifier(target: name, class: `class`, method: method)
        }
    }

    private static func description(target: String, class: String?, method: String?) -> String {
        var description = target
        if let `class` {
            description += "/\(`class`)"
        }
        if let method {
            description += "/\(method)"
        }
        return description
    }
}

extension String? {
    fileprivate var isEmptyButNotNil: Bool {
        if let self, self.isEmpty {
            return true
        }
        return false
    }
}
