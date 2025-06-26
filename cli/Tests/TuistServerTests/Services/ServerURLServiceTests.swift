import Foundation
import Mockable
import Testing
import TuistSupport

@testable import TuistServer

struct ServerURLServiceTests {
    let subject = ServerEnvironmentService()

    @Test(.withMockedEnvironment()) func returns_the_value_from_tuist_url_env_variable_when_present_and_valid() throws {
        // Given
        let tuistURLString = "https://tuist.dev"
        let tuistURL = URL(string: tuistURLString)!
        let configURL = URL(string: "https://tuist.config")!
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = ["TUIST_URL": tuistURLString]

        // When
        #expect(try subject.url(configServerURL: configURL) == tuistURL)
    }

    @Test(.withMockedEnvironment()) func returns_the_value_from_the_config_when_no_env_variables_are_present() throws {
        // Given
        let configURL = URL(string: "https://tuist.config")!
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]

        // When
        #expect(
            try subject.url(configServerURL: configURL) == configURL
        )
    }
}
