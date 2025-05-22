import Foundation
import Mockable
import Testing
import TuistSupport

@testable import TuistServerCore

struct ServerURLServiceTests {
    let subject = ServerURLService()

    @Test func returns_the_value_from_tuist_url_env_variable_when_present_and_valid() throws {
        // Given
        let tuistURLString = "https://tuist.dev"
        let tuistURL = URL(string: tuistURLString)!
        let envVariables = ["TUIST_URL": tuistURLString]
        let configURL = URL(string: "https://tuist.config")!

        // When
        #expect(try subject.url(configServerURL: configURL, envVariables: envVariables) == tuistURL)
    }

    @Test func returns_the_value_from_cirrus_tuist_cache_url_env_variable_when_present_and_valid()
        throws
    {
        // Given
        let tuistURLString = "https://cirrus.dev"
        let tuistURL = URL(string: tuistURLString)!
        let envVariables = [Constants.EnvironmentVariables.cirrusTuistCacheURL: tuistURLString]
        let configURL = URL(string: "https://tuist.config")!

        // When
        #expect(try subject.url(configServerURL: configURL, envVariables: envVariables) == tuistURL)
    }

    @Test func returns_the_value_from_the_config_when_no_env_variables_are_present() throws {
        // Given
        let envVariables: [String: String] = [:]
        let configURL = URL(string: "https://tuist.config")!

        // When
        #expect(
            try subject.url(configServerURL: configURL, envVariables: envVariables) == configURL
        )
    }
}
