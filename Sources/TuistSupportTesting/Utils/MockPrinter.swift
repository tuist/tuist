import Basic
import Foundation
import TuistSupport
import XCTest

public final class MockPrinter: Printing {
    var standardOutput: String = ""
    var standardError: String = ""

    public func print(_ text: PrintableString) {
        standardOutput.append("\(text)\n")
    }

    public func print(section: PrintableString) {
        standardOutput.append("\(section)\n")
    }

    public func print(warning: PrintableString) {
        standardOutput.append("\(warning)\n")
    }

    public func print(deprecation: PrintableString) {
        standardOutput.append("\(deprecation)\n")
    }

    public func print(errorMessage: PrintableString) {
        standardError.append("\(errorMessage)\n")
    }

    public func print(error: Error) {
        standardError.append("\(error.localizedDescription)\n")
    }

    public func print(success: PrintableString) {
        standardOutput.append("\(success)\n")
    }

    public func print(subsection: PrintableString) {
        standardOutput.append("\(subsection)\n")
    }

    func standardOutputMatches(with pattern: String) -> Bool {
        standardOutput.contains(pattern)
    }

    func standardErrorMatches(with pattern: String) -> Bool {
        standardError.contains(pattern)
    }
}
