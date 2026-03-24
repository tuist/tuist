import Testing
import TuistTesting
@testable import ProjectDescription

struct PluginTests {
    @Test func codable() throws {
        let subject = Plugin(name: "TestPlugin")
        #expect(try isCodableRoundTripable(subject))
    }
}
