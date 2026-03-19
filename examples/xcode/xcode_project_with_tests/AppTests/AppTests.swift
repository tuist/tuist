import AppFramework
import Testing
@testable import App

struct AppTests {
    @Test func example() async throws {
        try await Task.sleep(for: .milliseconds(500))
        #expect(AppFramework().hello() == "AppFramework.hello()")
    }
}
