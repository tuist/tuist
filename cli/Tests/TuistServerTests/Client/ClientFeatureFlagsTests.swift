import Testing
import TuistEnvironment

@testable import TuistServer

struct ClientFeatureFlagsTests {
    @Test func header_value_is_nil_when_no_flag_variable_is_set() async {
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

    @Test func kura_is_not_enabled_when_no_variable_is_set() async {
        let environment = Environment(variables: [:], arguments: [])

        let containsKura = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.contains("kura")
        }

        #expect(containsKura == false)
    }

    @Test(arguments: ["0", "false", "FALSE", "no", "", " 0 "])
    func a_falsey_value_disables_a_flag(value: String) async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_A": value,
            ],
            arguments: []
        )

        let (containsA, headerValue) = await Environment.$current.withValue(environment) {
            (ClientFeatureFlags.contains("a"), ClientFeatureFlags.headerValue())
        }

        #expect(containsA == false)
        #expect(headerValue == nil)
    }

    @Test(arguments: ["1", "true", "yes", "enabled"])
    func a_truthy_value_enables_a_flag(value: String) async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_A": value,
            ],
            arguments: []
        )

        let (containsA, headerValue) = await Environment.$current.withValue(environment) {
            (ClientFeatureFlags.contains("a"), ClientFeatureFlags.headerValue())
        }

        #expect(containsA)
        #expect(headerValue == "A")
    }

    @Test func a_flag_declared_in_lowercase_is_enabled() async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_coverage": "1",
            ],
            arguments: []
        )

        let (containsCoverage, headerValue) = await Environment.$current.withValue(environment) {
            (ClientFeatureFlags.contains("COVERAGE"), ClientFeatureFlags.headerValue())
        }

        #expect(containsCoverage)
        #expect(headerValue == "COVERAGE")
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

    @Test func a_falsey_value_disables_only_the_flag_it_names() async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_B": "0",
                "TUIST_FEATURE_FLAG_A": "1",
            ],
            arguments: []
        )

        let headerValue = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.headerValue()
        }

        #expect(headerValue == "A")
    }

    @Test func contains_matches_feature_flags_case_insensitively() async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_EXPERIMENT": "1",
            ],
            arguments: []
        )

        let containsExperiment = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.contains("experiment")
        }

        #expect(containsExperiment)
    }

    @Test func environment_variables_forward_the_flags_to_processes_that_do_not_inherit_the_environment() async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_COVERAGE": "1",
                "TUIST_TOKEN": "token",
            ],
            arguments: []
        )

        let variables = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.environmentVariables()
        }

        #expect(variables == ["TUIST_FEATURE_FLAG_COVERAGE": "1"])

        let forwarded = Environment(variables: variables, arguments: [])
        let containsCoverage = await Environment.$current.withValue(forwarded) {
            ClientFeatureFlags.contains("coverage")
        }

        #expect(containsCoverage)
    }
}
