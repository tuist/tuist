import Foundation
@testable import xcbuddykit

final class MockCommandsContext: CommandsContexting {
    let mockPrinter: MockPrinter
    var printer: Printing { return mockPrinter }

    init(printer: MockPrinter = MockPrinter()) {
        mockPrinter = printer
    }
}
