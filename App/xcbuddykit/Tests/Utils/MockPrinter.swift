import Foundation
@testable import xcbuddykit

final class MockPrinter: Printing {
    var printArgs: [String] = []

    func print(_ text: String) {
        printArgs.append(text)
    }
}
