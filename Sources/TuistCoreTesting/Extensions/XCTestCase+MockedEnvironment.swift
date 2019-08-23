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
        // swiftlint:disable force_try
        FileHandler.shared = try! MockFileHandler()
    }
}
