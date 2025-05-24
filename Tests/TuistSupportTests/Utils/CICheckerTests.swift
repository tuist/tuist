import Foundation
import Testing
import TuistSupport
import TuistSupportTesting

struct CICheckerTests {
    var subject: CIChecker = .init()

    @Test(.withMockedEnvironment) func when_ci_env_variable_is_present() throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = ["CI": "1"]

        // When
        let got = subject.isCI()

        // Then
        #expect(got == true)
    }

    @Test(.withMockedEnvironment) func when_ci_env_variable_is_absent() throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]

        // When
        let got = subject.isCI()

        // Then
        #expect(got == false)
    }
}
