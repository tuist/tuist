import Foundation
import TuistCore
import XCTest

extension XCTestCase {
    func mockEnvironment() {
        mockPrinter()
    }

    func mockPrinter() {
        Printer.shared = MockPrinter()
    }
}
