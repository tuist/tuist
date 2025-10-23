import Foundation
import Path
import Testing
@testable import TuistSupport
@testable import TuistTesting

struct EnvironmentTests {
    // MARK: - Cache Directory Tests

    @Test(.withMockedEnvironment()) func cacheDirectory_withTuistXDGCacheHome() throws {
        // Given
        let customPath = "/custom/cache/path"
        Environment.mocked?.variables["TUIST_XDG_CACHE_HOME"] = customPath

        // When
        let result = Environment.mocked?.cacheDirectory

        // Then
        #expect(result?.pathString == "\(customPath)/tuist")
    }

    @Test(.withMockedEnvironment()) func cacheDirectory_withXDGCacheHome() throws {
        // Given
        let customPath = "/custom/cache/path"
        Environment.mocked?.variables["XDG_CACHE_HOME"] = customPath

        // When
        let result = Environment.mocked?.cacheDirectory

        // Then
        #expect(result?.pathString == "\(customPath)/tuist")
    }

    @Test(.withMockedEnvironment()) func cacheDirectory_tuistPrefixTakesPrecedence() throws {
        // Given
        let tuistPath = "/tuist/cache"
        let xdgPath = "/xdg/cache"
        Environment.mocked?.variables["TUIST_XDG_CACHE_HOME"] = tuistPath
        Environment.mocked?.variables["XDG_CACHE_HOME"] = xdgPath

        // When
        let result = Environment.mocked?.cacheDirectory

        // Then - TUIST_ prefix should take precedence
        #expect(result?.pathString == "\(tuistPath)/tuist")
    }

    // MARK: - State Directory Tests

    @Test(.withMockedEnvironment()) func stateDirectory_withTuistXDGStateHome() throws {
        // Given
        let customPath = "/custom/state/path"
        Environment.mocked?.variables["TUIST_XDG_STATE_HOME"] = customPath

        // When
        let result = Environment.mocked?.stateDirectory

        // Then
        #expect(result?.pathString == "\(customPath)/tuist")
    }

    @Test(.withMockedEnvironment()) func stateDirectory_withXDGStateHome() throws {
        // Given
        let customPath = "/custom/state/path"
        Environment.mocked?.variables["XDG_STATE_HOME"] = customPath

        // When
        let result = Environment.mocked?.stateDirectory

        // Then
        #expect(result?.pathString == "\(customPath)/tuist")
    }

    @Test(.withMockedEnvironment()) func stateDirectory_tuistPrefixTakesPrecedence() throws {
        // Given
        let tuistPath = "/tuist/state"
        let xdgPath = "/xdg/state"
        Environment.mocked?.variables["TUIST_XDG_STATE_HOME"] = tuistPath
        Environment.mocked?.variables["XDG_STATE_HOME"] = xdgPath

        // When
        let result = Environment.mocked?.stateDirectory

        // Then - TUIST_ prefix should take precedence
        #expect(result?.pathString == "\(tuistPath)/tuist")
    }

    // MARK: - Config Directory Tests

    @Test(.withMockedEnvironment()) func configDirectory_withTuistXDGConfigHome() throws {
        // Given
        let customPath = "/custom/config/path"
        Environment.mocked?.variables["TUIST_XDG_CONFIG_HOME"] = customPath

        // When
        let result = Environment.mocked?.configDirectory

        // Then
        #expect(result?.pathString == "\(customPath)/tuist")
    }

    @Test(.withMockedEnvironment()) func configDirectory_withXDGConfigHome() throws {
        // Given
        let customPath = "/custom/config/path"
        Environment.mocked?.variables["XDG_CONFIG_HOME"] = customPath

        // When
        let result = Environment.mocked?.configDirectory

        // Then
        #expect(result?.pathString == "\(customPath)/tuist")
    }

    @Test(.withMockedEnvironment()) func configDirectory_tuistPrefixTakesPrecedence() throws {
        // Given
        let tuistPath = "/tuist/config"
        let xdgPath = "/xdg/config"
        Environment.mocked?.variables["TUIST_XDG_CONFIG_HOME"] = tuistPath
        Environment.mocked?.variables["XDG_CONFIG_HOME"] = xdgPath

        // When
        let result = Environment.mocked?.configDirectory

        // Then - TUIST_ prefix should take precedence
        #expect(result?.pathString == "\(tuistPath)/tuist")
    }

    // MARK: - Data Directory Tests

    @Test(.withMockedEnvironment()) func dataDirectory_withTuistXDGDataHome() throws {
        // Given
        let customPath = "/custom/data/path"
        Environment.mocked?.variables["TUIST_XDG_DATA_HOME"] = customPath

        // When
        let result = Environment.mocked?.dataDirectory

        // Then
        #expect(result?.pathString == "\(customPath)/tuist")
    }

    @Test(.withMockedEnvironment()) func dataDirectory_withXDGDataHome() throws {
        // Given
        let customPath = "/custom/data/path"
        Environment.mocked?.variables["XDG_DATA_HOME"] = customPath

        // When
        let result = Environment.mocked?.dataDirectory

        // Then
        #expect(result?.pathString == "\(customPath)/tuist")
    }

    @Test(.withMockedEnvironment()) func dataDirectory_tuistPrefixTakesPrecedence() throws {
        // Given
        let tuistPath = "/tuist/data"
        let xdgPath = "/xdg/data"
        Environment.mocked?.variables["TUIST_XDG_DATA_HOME"] = tuistPath
        Environment.mocked?.variables["XDG_DATA_HOME"] = xdgPath

        // When
        let result = Environment.mocked?.dataDirectory

        // Then - TUIST_ prefix should take precedence
        #expect(result?.pathString == "\(tuistPath)/tuist")
    }
}
