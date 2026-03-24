import Testing
import TuistTesting
@testable import ProjectDescription

struct DefaultSettingsTests {
    @Test func recommended_toJSON() throws {
        let subject = DefaultSettings.recommended(excluding: ["exclude"])
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func essential_toJSON() throws {
        let subject = DefaultSettings.essential(excluding: ["exclude"])
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func none_toJSON() throws {
        let subject = DefaultSettings.none
        #expect(try isCodableRoundTripable(subject))
    }
}
