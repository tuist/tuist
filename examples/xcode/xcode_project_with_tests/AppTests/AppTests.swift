import AppFramework
import Testing
@testable import App

struct AppTests {
    @Test func example() async throws {
        #expect(AppFramework().hello() == "AppFramework.hello()")
    }

    @Test(arguments: ["hello", "world", "test"])
    func parameterized(value: String) {
        #expect(!value.isEmpty)
        if value == "test" {
            #expect(value.count > 10, "Expected long string but got: \(value)")
        }
    }
}
