import Foundation
@testable import xpmKit

final class MockCommandCheck: CommandChecking {
    var checkStub: ((String) throws -> Void)?

    func check(command: String) throws {
        try checkStub?(command)
    }
}
