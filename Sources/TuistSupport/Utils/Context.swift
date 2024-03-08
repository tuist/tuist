import Foundation
import Logging

public protocol Context {
    var environment: Environmenting { get }
}

#if MOCKING
    public class MockContext: Context {
        public var environment: Environmenting { mockEnvironment }
        public var mockEnvironment: MockEnvironment
        public let testId: String

        public init(testId: String = UUID().uuidString) {
            self.testId = testId
            mockEnvironment = MockEnvironment()
        }
    }
#endif

public class TuistContext: Context {
    @available(*, deprecated, message: """
    The usage of TuistContext.shared is discouraged because it limits the ability to run tests in parallel. Existing usages in the codebase
    are pending a refactor, so please avoid cargo-culting the pattern.
    """)
    public private(set) static var shared: Context!

    public let environment: Environmenting

    public convenience init() throws {
        let environment = try Environment()
        try self.init(environment: environment)
    }

    init(environment: Environmenting) throws {
        self.environment = environment
    }

    public static func initializeSharedInstace() throws {
        TuistContext.shared = try TuistContext()
    }
}
