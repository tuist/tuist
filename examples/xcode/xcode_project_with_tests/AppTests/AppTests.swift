import AppFramework
import Testing
@testable import App

struct AppTests {
    @Test func example() async throws {
        #expect(AppFramework().hello() == "AppFramework.hello()")
    }
}
