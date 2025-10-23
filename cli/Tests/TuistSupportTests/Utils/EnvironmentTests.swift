import Foundation
import Path
import Testing
@testable import TuistSupport
@testable import TuistTesting

struct EnvironmentTests {
    // MARK: - Cache Directory Tests

    @Test() func cacheDirectory_withTuistXDGCacheHome() throws {
        // Given
        let customPath = "/custom/cache/path"

        let subject = Environment(variables: [
            "TUIST_XDG_CACHE_HOME": customPath,
        ])

        // When
        let result = subject.cacheDirectory

        // Then
        #expect(result.pathString == "\(customPath)/tuist")
    }

    @Test() func cacheDirectory_withXDGCacheHome() throws {
        // Given
        let customPath = "/custom/cache/path"

        let subject = Environment(variables: [
            "XDG_CACHE_HOME": customPath,
        ])

        // When
        let result = subject.cacheDirectory

        // Then
        #expect(result.pathString == "\(customPath)/tuist")
    }

    @Test() func cacheDirectory_tuistPrefixTakesPrecedence() throws {
        // Given
        let tuistPath = "/tuist/cache"
        let xdgPath = "/xdg/cache"

        let subject = Environment(variables: [
            "TUIST_XDG_CACHE_HOME": tuistPath,
            "XDG_CACHE_HOME": xdgPath,
        ])

        // When
        let result = subject.cacheDirectory

        // Then
        #expect(result.pathString == "\(tuistPath)/tuist")
    }

    // MARK: - State Directory Tests

    @Test() func stateDirectory_withTuistXDGStateHome() throws {
        // Given
        let customPath = "/custom/state/path"

        let subject = Environment(variables: [
            "TUIST_XDG_STATE_HOME": customPath,
        ])

        // When
        let result = subject.stateDirectory

        // Then
        #expect(result.pathString == "\(customPath)/tuist")
    }

    @Test() func stateDirectory_withXDGStateHome() throws {
        // Given
        let customPath = "/custom/state/path"

        let subject = Environment(variables: [
            "XDG_STATE_HOME": customPath,
        ])

        // When
        let result = subject.stateDirectory

        // Then
        #expect(result.pathString == "\(customPath)/tuist")
    }

    @Test() func stateDirectory_tuistPrefixTakesPrecedence() throws {
        // Given
        let tuistPath = "/tuist/state"
        let xdgPath = "/xdg/state"

        let subject = Environment(variables: [
            "TUIST_XDG_STATE_HOME": tuistPath,
            "XDG_STATE_HOME": xdgPath,
        ])

        // When
        let result = subject.stateDirectory

        // Then
        #expect(result.pathString == "\(tuistPath)/tuist")
    }

    // MARK: - Config Directory Tests

    @Test() func configDirectory_withTuistXDGConfigHome() throws {
        // Given
        let customPath = "/custom/config/path"

        let subject = Environment(variables: [
            "TUIST_XDG_CONFIG_HOME": customPath,
        ])

        // When
        let result = subject.configDirectory

        // Then
        #expect(result.pathString == "\(customPath)/tuist")
    }

    @Test() func configDirectory_withXDGConfigHome() throws {
        // Given
        let customPath = "/custom/config/path"

        let subject = Environment(variables: [
            "XDG_CONFIG_HOME": customPath,
        ])

        // When
        let result = subject.configDirectory

        // Then
        #expect(result.pathString == "\(customPath)/tuist")
    }

    @Test() func configDirectory_tuistPrefixTakesPrecedence() throws {
        // Given
        let tuistPath = "/tuist/config"
        let xdgPath = "/xdg/config"

        let subject = Environment(variables: [
            "TUIST_XDG_CONFIG_HOME": tuistPath,
            "XDG_CONFIG_HOME": xdgPath,
        ])

        // When
        let result = subject.configDirectory

        // Then
        #expect(result.pathString == "\(tuistPath)/tuist")
    }
}
