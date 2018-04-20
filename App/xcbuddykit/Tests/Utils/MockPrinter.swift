import Foundation
@testable import xcbuddykit

final class MockPrinter: Printing {
    var printArgs: [String] = []
    var printErrorArgs: [Error] = []

    func print(_ text: String) {
        printArgs.append(text)
    }

    func print(error: Error) {
        printErrorArgs.append(error)
    }
}
