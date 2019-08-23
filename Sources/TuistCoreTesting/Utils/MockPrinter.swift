import Basic
import Foundation
import TuistCore
import XCTest

public final class MockPrinter: Printing {
    var standardOutput: String = ""
    var standardError: String = ""

    public func print(_ text: String) {
        print(text, output: .standardOputput)
    }

    public func print(_ text: String, output: PrinterOutput) {
        if output == .standardOputput {
            standardOutput.append("\(text)\n")
        } else {
            standardError.append("\(text)\n")
        }
    }

    public func print(_ text: String, color _: TerminalController.Color) {
        standardOutput.append("\(text)\n")
    }

    public func print(section: String) {
        standardOutput.append("\(section)\n")
    }

    public func print(warning: String) {
        standardOutput.append("\(warning)\n")
    }

    public func print(deprecation: String) {
        standardOutput.append("\(deprecation)\n")
    }

    public func print(errorMessage: String) {
        standardError.append("\(errorMessage)\n")
    }

    public func print(error: Error) {
        standardError.append("\(error.localizedDescription)\n")
    }

    public func print(success: String) {
        standardOutput.append("\(success)\n")
    }

    public func print(subsection: String) {
        standardOutput.append("\(subsection)\n")
    }

    func standardOutputMatches(with pattern: String) -> Bool {
        // swiftlint:disable:next force_try
        return standardOutput.contains(pattern)
    }

    func standardErrorMatches(with pattern: String) -> Bool {
        // swiftlint:disable:next force_try
        return standardError.contains(pattern)
    }
}

extension XCTestCase {
    func XCTAssertPrinterOutputContains(_ expected: String, file: StaticString = #file, line: UInt = #line) {
        guard let printer = sharedMockPrinter(file: file, line: line) else { return }

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

    func XCTAssertPrinterErrorContains(_ expected: String, file: StaticString = #file, line: UInt = #line) {
        guard let printer = sharedMockPrinter(file: file, line: line) else { return }

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

    fileprivate func sharedMockPrinter(file: StaticString = #file, line: UInt = #line) -> MockPrinter? {
        guard let mock = Printer.shared as? MockPrinter else {
            let message = "Printer.shared hasn't been mocked." +
                "You can call mockPrinter(), or mockEnvironment() to mock the printer or the environment respectively."
            XCTFail(message, file: file, line: line)
            return nil
        }
        return mock
    }
}
