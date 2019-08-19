import Foundation
import TuistCore
import XCTest

public final class MockContext: Contexting {
    // Printer

    public var printer: Printing = MockPrinter()
    fileprivate var mockPrinter: MockPrinter { return printer as! MockPrinter }

    // Deprecator

    public var deprecator: Deprecating = MockDeprecator()
    fileprivate var mockDeprecator: MockDeprecator { return deprecator as! MockDeprecator }
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

extension XCTestCase {
    func XCTAssertPrinterOutputContains(_ expected: String, file: StaticString = #file, line: UInt = #line) {
        guard let context = sharedMockContext(file: file, line: line) else { return }

        let message = """
        The standard output:
        ===========
        \(context.mockPrinter.standardOutput)
        
        Doesn't contain the expected output:
        ===========
        \(expected)
        """
        XCTAssertTrue(context.mockPrinter.standardOutputMatches(with: expected), message, file: file, line: line)
    }

    func XCTAssertPrinterErrorContains(_ expected: String, file: StaticString = #file, line: UInt = #line) {
        guard let context = sharedMockContext(file: file, line: line) else { return }
        
        let message = """
        The standard error:
        ===========
        \(context.mockPrinter.standardError)
        
        Doesn't contain the expected output:
        ===========
        \(expected)
        """
        XCTAssertTrue(context.mockPrinter.standardErrorMatches(with: expected), message, file: file, line: line)
    }
    
    fileprivate func sharedMockContext(file: StaticString = #file, line: UInt = #line) -> MockContext?  {
        guard let mock = Context.shared as? MockContext else {
            XCTFail("Context.shared hasn't been mocked. Call Context.mockSharedContext() from the test's setUp method.", file: file, line: line)
            return nil
        }
        return mock
    }
}
