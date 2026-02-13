import Foundation
import Testing
@testable import App

struct AppTests {
    @Test func example() async throws {
        fatalError("intentional crash for testing")
    }
}

@Test func topLevelTest() async throws {
    #expect(true == true)
}
