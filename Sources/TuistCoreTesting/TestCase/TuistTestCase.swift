import Basic
import Foundation
import XCTest

@testable import TuistCore

public class TuistTestCase: XCTestCase {
    fileprivate var temporaryDirectory: TemporaryDirectory!
    public var printer: MockPrinter!

    public override func setUp() {
        super.setUp()

        // Printer
        printer = MockPrinter()
        Printer.shared = printer
    }

    public override func tearDown() {
        // Printer
        printer = nil
        Printer.shared = Printer()

        temporaryDirectory = nil
        super.tearDown()
    }

    public func temporaryPath() throws -> AbsolutePath {
        if temporaryDirectory == nil {
            temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        }
        return temporaryDirectory.path
    }

    public func XCTAssertPrinterOutputContains(_ expected: String, file: StaticString = #file, line: UInt = #line) {
        let message = """
        The standard output:
        ===========
        \(printer.standardOutput)
        
        Doesn't contain the expected output:
        ===========
        \(expected)
        """
        XCTAssertTrue(printer.standardOutputMatches(with: expected), message, file: file, line: line)
    }

    public func XCTAssertPrinterErrorContains(_ expected: String, file: StaticString = #file, line: UInt = #line) {
        let message = """
        The standard error:
        ===========
        \(printer.standardError)
        
        Doesn't contain the expected output:
        ===========
        \(expected)
        """
        XCTAssertTrue(printer.standardErrorMatches(with: expected), message, file: file, line: line)
    }
}
