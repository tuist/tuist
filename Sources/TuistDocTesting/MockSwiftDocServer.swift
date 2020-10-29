import TSCBasic
import TuistDoc
@testable import TuistCore

public final class MockSwiftDocServer: SwiftDocServing {
    public static var stubIndexName: String!
    public static var indexName: String { stubBaseURL }

    public static var stubBaseURL: String!
    public static var baseURL: String { stubBaseURL }

    public var stubError: Error?

    public init() {}

    public func serve(path _: AbsolutePath, port _: UInt16) throws {
        guard let error = stubError else { return }
        throw error
    }
}
