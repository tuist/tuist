import Basic
import Foundation
import TuistCore

public final class MockPrinter: Printing {
    var standardOutput: String = ""
    var standardError: String = ""

    public var printArgs: [String] = []
    public var printWithColorArgs: [(String, TerminalController.Color)] = []
    public var printErrorArgs: [Error] = []
    public var printSectionArgs: [String] = []
    public var printSubsectionArgs: [String] = []
    public var printErrorMessageArgs: [String] = []
    public var printSuccessArgs: [String] = []
    public var printWarningArgs: [String] = []
    public var printDeprecationArgs: [String] = []
    public var printImportantArgs: [String] = []

    public func print(_ text: String) {
        printArgs.append(text)
        standardOutput.append(text)
    }

    public func print(_ text: String, color: TerminalController.Color) {
        printWithColorArgs.append((text, color))
        standardOutput.append("\(text)\n")
    }

    public func print(section: String) {
        printSectionArgs.append(section)
        standardOutput.append("\(section)\n")
    }

    public func print(warning: String) {
        printWarningArgs.append(warning)
        standardOutput.append("\(warning)\n")
    }

    public func print(deprecation: String) {
        printDeprecationArgs.append(deprecation)
        standardOutput.append("\(deprecation)\n")
    }

    public func print(errorMessage: String) {
        printErrorMessageArgs.append(errorMessage)
        standardError.append("\(errorMessage)\n")
    }

    public func print(error: Error) {
        printErrorArgs.append(error)
        standardError.append("\(error.localizedDescription)\n")
    }

    public func print(importantText: String) {
        printImportantArgs.append(importantText)
        standardOutput.append("\(importantText)\n")
    }

    public func print(success: String) {
        printSuccessArgs.append(success)
        standardOutput.append("\(success)\n")
    }

    public func print(subsection: String) {
        printSubsectionArgs.append(subsection)
        standardOutput.append("\(subsection)\n")
    }

    func standardOutputMatches(with pattern: String) -> Bool {
        // swiftlint:disable:next force_try
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        return regex.firstMatch(in: standardOutput, options: [], range: NSRange(location: 0, length: standardOutput.count)) != nil
    }

    func standardErrorMatches(with pattern: String) -> Bool {
        // swiftlint:disable:next force_try
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        return regex.firstMatch(in: standardError, options: [], range: NSRange(location: 0, length: standardError.count)) != nil
    }
}
