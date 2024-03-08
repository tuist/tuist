import Foundation
import Logging

public protocol Context {
    var environment: Environmenting { get }
    var logger: Logger! { get }
}

#if MOCKING
public class MockContext: Context {
        public var logHandler: TestLogHandler
        public var environment: Environmenting
        public var logger: Logging.Logger!
        public var mockEnvironment: MockEnvironment { environment as! MockEnvironment }

        public init(testId: String = UUID().uuidString) {
            environment = MockEnvironment()
            logHandler = TestLogHandler(testId: testId)
            logger = Logger(label: "io.tuist.test.\(testId)", factory: { _ in self.logHandler })
        }
    }
#endif

public class TuistContext: Context {
    public let environment: Environmenting
    public let logger: Logger!

    public convenience init() async throws {
        let environment = try Environment()
        let logger = await Logger.tuist(environment: environment)
        try self.init(environment: environment, logger: logger)
    }

    init(environment: Environmenting, logger: Logger) throws {
        self.environment = environment
        self.logger = logger
    }
}
