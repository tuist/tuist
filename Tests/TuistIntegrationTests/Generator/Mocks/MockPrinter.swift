import Basic
import Foundation
import TuistSupport

class MockPrinter: Printing {
    func print(_: PrintableString) {}

    func print(section _: PrintableString) {}

    func print(subsection _: PrintableString) {}

    func print(warning _: PrintableString) {}

    func print(error _: Error) {}

    func print(success _: PrintableString) {}

    func print(errorMessage _: PrintableString) {}

    func print(deprecation _: PrintableString) {}
}
