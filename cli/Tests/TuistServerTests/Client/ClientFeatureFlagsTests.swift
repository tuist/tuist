import Testing
import TuistEnvironment

@testable import TuistServer

struct ClientFeatureFlagsTests {
    @Test func header_value_is_nil_when_no_feature_flags_are_present() async {
        let environment = Environment(
            variables: [
                "TUIST_TOKEN": "token",
                "CI": "true",
            ],
            arguments: []
        )

        let headerValue = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.headerValue()
        }

        #expect(headerValue == nil)
    }

    @Test func header_value_encodes_feature_flags_as_a_comma_separated_list() async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_B": "enabled",
                "TUIST_FEATURE_FLAG_A": "1",
                "TUIST_TOKEN": "token",
            ],
            arguments: []
        )

        let headerValue = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.headerValue()
        }

        #expect(headerValue == "A,B")
    }
}
