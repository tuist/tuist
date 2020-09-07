import TuistDoc
import TSCBasic
@testable import TuistCore

public final class MockSwiftDocServer: SwiftDocServing {
    public var stubBaseURL: String!
    public var baseURL: String { stubBaseURL }
    
    public var stubError: Error?
    
    public func serve(path: AbsolutePath, port: UInt16) throws {
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
