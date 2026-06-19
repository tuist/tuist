import Foundation
import Testing

@testable import MacFramework

struct MacFrameworkGreetingTests {
    @Test func greeting_isStable() {
        #expect(MacFramework().hello() == "MacFramework.hello()")
    }
}

struct MacFrameworkValueTests {
    @Test func greeting_isNotEmpty() {
        #expect(!MacFramework().hello().isEmpty)
    }
}
