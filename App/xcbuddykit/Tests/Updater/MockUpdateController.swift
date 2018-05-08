import Foundation
@testable import xcbuddykit

class MockUpdateController: UpdateControlling {
    var checkAndUpdateFromAppCount: UInt = 0
    var checkAndUpdateFromConsoleCount: UInt = 0

    func checkAndUpdateFromApp(sender _: Any) {
        checkAndUpdateFromAppCount += 1
    }

    func checkAndUpdateFromConsole(context: Contexting) throws {
        checkAndUpdateFromConsoleCount += 1
    }
}
