import TSCBasic
import TuistDoc
@testable import TuistCore

public final class MockSwiftDocServer: SwiftDocServing {
    public var stubBaseURL: String!
    public var baseURL: String { stubBaseURL }

    public var stubError: Error?

    public init() {}

    public func serve(path _: AbsolutePath, port _: UInt16) throws {
        guard let error = stubError else { return }
        throw error
    }
}

// MARK: - Error

public extension MockSwiftDocServer {
    enum MockError: Error {
        case mockError
    }
}
