import Testing
import TuistEnvironment

@testable import TuistServer

struct ClientFeatureFlagsTests {
    @Test func header_value_includes_built_in_feature_flags_when_no_environment_feature_flags_are_present() async {
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

        #expect(headerValue == "shard-skip-testing")
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

        #expect(headerValue == "A,B,shard-skip-testing")
    }

    @Test func contains_matches_feature_flags_case_insensitively() async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_KURA": "1",
            ],
            arguments: []
        )

        let containsKura = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.contains("kura")
        }

        #expect(containsKura)
    }

    @Test func contains_matches_built_in_feature_flags() async {
        let environment = Environment(variables: [:], arguments: [])

        let containsShardSkipTesting = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.contains("SHARD-SKIP-TESTING")
        }

        #expect(containsShardSkipTesting)
    }
}
