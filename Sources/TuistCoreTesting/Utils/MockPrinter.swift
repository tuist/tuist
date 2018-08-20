import Basic
import Foundation
import TuistCore

public final class MockPrinter: Printing {
    public var printArgs: [String] = []
    public var printWithColorArgs: [(String, TerminalController.Color)] = []
    public var printErrorArgs: [Error] = []
    public var printSectionArgs: [String] = []
    public var printErrorMessageArgs: [String] = []
    public var printSuccessArgs: [String] = []
    public var printWarningArgs: [String] = []

    public func print(_ text: String) {
        printArgs.append(text)
    }

    public func print(_ text: String, color: TerminalController.Color) {
        printWithColorArgs.append((text, color))
    }

    public func print(section: String) {
        printSectionArgs.append(section)
    }

    public func print(warning: String) {
        printWarningArgs.append(warning)
    }

    public func print(errorMessage: String) {
        printErrorMessageArgs.append(errorMessage)
    }

    public func print(error: Error) {
        printErrorArgs.append(error)
    }

    public func print(success: String) {
        printSuccessArgs.append(success)
    }
}
