import Foundation
import Testing
import TuistTesting

@testable import ProjectDescription

struct ConfigurationNameTests {
    @Test func test_codable() throws {
        #expect(try isCodableRoundTripable(ConfigurationName.debug))
        #expect(try isCodableRoundTripable(ConfigurationName.release))
    }
}
