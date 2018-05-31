import Foundation
@testable import xpmKit

class MockUpdateController: UpdateControlling {
    var checkAndUpdateFromAppCount: UInt = 0
    var checkAndUpdateFromConsoleCount: UInt = 0

    func checkAndUpdateFromApp(sender _: Any) {
        checkAndUpdateFromAppCount += 1
    }

    func checkAndUpdateFromConsole(context _: Contexting) throws {
        checkAndUpdateFromConsoleCount += 1
    }
}
