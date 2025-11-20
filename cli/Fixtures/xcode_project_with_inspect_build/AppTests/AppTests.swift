import Foundation
import Testing
@testable import App

struct AppTests {
    @Test func example() async throws {
        #expect(true == true)
    }
}

@Test func topLevelTest() async throws {
    #expect(true == true)
}
