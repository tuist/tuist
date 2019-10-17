import Basic
import Foundation
import TuistCore

class MockPrinter: Printing {
    func print(_: String) {}

    func print(section _: String) {}

    func print(subsection _: String) {}

    func print(warning _: String) {}

    func print(error _: Error) {}

    func print(success _: String) {}

    func print(errorMessage _: String) {}

    func print(deprecation _: String) {}
}
