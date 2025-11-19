import Foundation
import Testing
@testable import App

struct AppTests {
    @Test func example() async throws {
        #expect(true == true)
    }

    @Test func failing() async throws {
        try await Task.sleep(for: .milliseconds(100))
        #expect(true == false)
    }
}

@Test func topLevelTest() async throws {
    #expect(true == true)
}
