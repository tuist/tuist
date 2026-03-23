import Testing
import TuistTesting
@testable import ProjectDescription

struct DefaultSettingsTests {
    @Test func test_recommended_toJSON() throws {
        let subject = DefaultSettings.recommended(excluding: ["exclude"])
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func test_essential_toJSON() throws {
        let subject = DefaultSettings.essential(excluding: ["exclude"])
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func test_none_toJSON() throws {
        let subject = DefaultSettings.none
        #expect(try isCodableRoundTripable(subject))
    }
}
