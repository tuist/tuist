import Foundation
@testable import xcbuddykit

final class MockPrinter: Printing {
    var printArgs: [String] = []
    var printErrorArgs: [Error] = []
    var printSectionArgs: [String] = []
    var printErrorMessageArgs: [String] = []

    func print(_ text: String) {
        printArgs.append(text)
    }

    func print(section: String) {
        printSectionArgs.append(section)
    }

    func print(errorMessage: String) {
        printErrorMessageArgs.append(errorMessage)
    }

    func print(error: Error) {
        printErrorArgs.append(error)
    }
}
