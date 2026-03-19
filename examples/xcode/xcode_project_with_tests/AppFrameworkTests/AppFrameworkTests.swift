import Testing
@testable import AppFramework

struct AppFrameworkTests {
    @Test func example() async throws {
        try await Task.sleep(for: .seconds(1))
        #expect(AppFramework().hello() == "AppFramework.hello()")
    }
}
