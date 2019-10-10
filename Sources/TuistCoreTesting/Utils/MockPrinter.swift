import Basic
import Foundation
import TuistCore
import XCTest

public final class MockPrinter: Printing {
    var standardOutput: String = ""
    var standardError: String = ""

    public func print(_ text: String) {
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
        return standardOutput.contains(pattern)
    }

    func standardErrorMatches(with pattern: String) -> Bool {
        return standardError.contains(pattern)
    }
}
