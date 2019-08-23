import Foundation
import TuistCore
import XCTest

extension XCTestCase {
    func mockEnvironment() {
        mockPrinter()
        mockFileHandler()
    }

    func mockPrinter() {
        Printer.shared = MockPrinter()
    }

    func mockFileHandler() {
        FileHandler.shared = try! MockFileHandler()
    }
}
