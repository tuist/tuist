import Testing
@testable import App

struct AppTests {
    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
    
    @Test func failing() async throws {
        try await Task.sleep(for: .milliseconds(100))
        #expect(true == false)
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
}

@Test func exampleee() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
}
