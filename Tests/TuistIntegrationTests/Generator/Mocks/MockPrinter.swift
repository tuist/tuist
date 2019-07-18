import Basic
import Foundation
import TuistCore

class MockPrinter: Printing {
    func print(_: String) {
        // Do nothing
    }

    func print(_: String, color _: TerminalController.Color) {
        // Do nothing
    }

    func print(section _: String) {
        // Do nothing
    }

    func print(subsection _: String) {
        // Do nothing
    }

    func print(warning _: String) {
        // Do nothing
    }

    func print(error _: Error) {
        // Do nothing
    }

    func print(success _: String) {
        // Do nothing
    }

    func print(errorMessage _: String) {
        // Do nothing
    }

    func print(importantText _: String) {
        // Do nothing
    }

    func print(deprecation _: String) {
        // Do nothing
    }
}
