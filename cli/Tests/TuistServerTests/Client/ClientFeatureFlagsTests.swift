import Testing
import TuistEnvironment

@testable import TuistServer

struct ClientFeatureFlagsTests {
    @Test func header_value_carries_the_default_enabled_flags_when_no_variable_is_set() async {
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

        #expect(headerValue == "KURA")
    }

    @Test func kura_is_enabled_when_no_variable_is_set() async {
        let environment = Environment(variables: [:], arguments: [])

        let containsKura = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.contains("kura")
        }

        #expect(containsKura)
    }

    @Test(arguments: ["0", "false", "FALSE", "no", "", " 0 "])
    func a_falsey_value_disables_a_default_enabled_flag(value: String) async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_KURA": value,
            ],
            arguments: []
        )

        let (containsKura, headerValue) = await Environment.$current.withValue(environment) {
            (ClientFeatureFlags.contains("kura"), ClientFeatureFlags.headerValue())
        }

        #expect(containsKura == false)
        #expect(headerValue == nil)
    }

    @Test(arguments: ["1", "true", "yes", "enabled"])
    func a_truthy_value_enables_a_flag(value: String) async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_KURA": value,
            ],
            arguments: []
        )

        let (containsKura, headerValue) = await Environment.$current.withValue(environment) {
            (ClientFeatureFlags.contains("kura"), ClientFeatureFlags.headerValue())
        }

        #expect(containsKura)
        #expect(headerValue == "KURA")
    }

    @Test func a_falsey_value_disables_a_flag_declared_in_lowercase() async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_kura": "0",
            ],
            arguments: []
        )

        let containsKura = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.contains("kura")
        }

        #expect(containsKura == false)
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

        #expect(headerValue == "A,B,KURA")
    }

    @Test func a_falsey_value_disables_only_the_flag_it_names() async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_KURA": "0",
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

    @Test func environment_variables_forward_an_opt_out_to_processes_that_do_not_inherit_the_environment() async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_KURA": "0",
                "TUIST_TOKEN": "token",
            ],
            arguments: []
        )

        let variables = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.environmentVariables()
        }

        #expect(variables == ["TUIST_FEATURE_FLAG_KURA": "0"])

        let forwarded = Environment(variables: variables, arguments: [])
        let containsKura = await Environment.$current.withValue(forwarded) {
            ClientFeatureFlags.contains("kura")
        }

        #expect(containsKura == false)
    }

    @Test func a_process_that_inherits_no_variables_computes_the_same_defaults() async {
        let environment = Environment(
            variables: [
                "TUIST_TOKEN": "token",
            ],
            arguments: []
        )

        let variables = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.environmentVariables()
        }

        #expect(variables.isEmpty)

        let forwarded = Environment(variables: variables, arguments: [])
        let containsKura = await Environment.$current.withValue(forwarded) {
            ClientFeatureFlags.contains("kura")
        }

        #expect(containsKura)
    }
}
