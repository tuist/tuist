import Testing
@testable import AppFramework

struct AppFrameworkTests {
    @Test func example() async throws {
        #expect(AppFramework().hello() == "AppFramework.hello()")
    }
}
