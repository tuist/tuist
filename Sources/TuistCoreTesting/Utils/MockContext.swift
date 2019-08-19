import Foundation
import TuistCore

public final class MockContext: Contexting {
    // Printer

    public var printer: Printing = MockPrinter()
    public var mockPrinter: MockPrinter { return printer as! MockPrinter }

    // Deprecator

    public var deprecator: Deprecating = MockDeprecator()
    public var mockDeprecator: MockDeprecator { return deprecator as! MockDeprecator }
}

extension Context {
    /// Mocks the shared context instance and returns the mock.
    ///
    /// - Returns: Mocked context.
    static func mockSharedContext() -> MockContext {
        let mock = MockContext()
        shared = mock
        return mock
    }
}
