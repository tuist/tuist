import Foundation
import XCTest

public extension XCTestCase {
    func XCTAssertStandardOutput(_ printer: MockPrinter, pattern: String) {
        XCTAssertTrue(printer.standardOutputMatches(with: pattern), """
        The pattern:
        \(pattern)
            
        Does not match the standard output:
        \(printer.standardOutput)
        """)
    }

    func XCTAssertStandarError(_ printer: MockPrinter, pattern: String) {
        XCTAssertTrue(printer.standardErrorMatches(with: pattern), """
        The pattern:
        \(pattern)
            
        Does not match the standard error:
        \(printer.standardError)
        """)
    }
}
