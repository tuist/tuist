import Foundation
import TuistCore
import XCTest

extension XCTestCase {
    func mockAllSystemInteractions() {
        mockPrinter()
        mockFileHandler()
        mockEnvironment()
    }

    func mockPrinter() {
        Printer.shared = MockPrinter()
    }

    func mockFileHandler() {
        // swiftlint:disable force_try
        FileHandler.shared = try! MockFileHandler()
    }

    func mockEnvironment() {
        // swiftlint:disable force_try
        Environment.shared = try! MockEnvironment()
    }
}
