import Foundation
import Path
import Testing
@testable import TuistEnvironment
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

    // MARK: - manifestLoadingVariables

    @Test() func manifestLoadingVariables_includesDefaults() throws {
        let subject = Environment(variables: [
            "TUIST_FOO": "1",
            "CI": "true",
            "DEVELOPER_DIR": "/some/xcode",
            "OPENSWIFTUI_LIBRARY_TYPE": "dynamic",
            "OTHER": "ignored",
        ])

        let result = subject.manifestLoadingVariables

        #expect(result["TUIST_FOO"] == "1")
        #expect(result["CI"] == "true")
        #expect(result["DEVELOPER_DIR"] == "/some/xcode")
        #expect(result["OPENSWIFTUI_LIBRARY_TYPE"] == nil)
        #expect(result["OTHER"] == nil)
    }

    @Test() func manifestLoadingVariables_includesAdditionalKeysExactMatch() async throws {
        let subject = Environment(variables: [
            "TUIST_FOO": "1",
            "OPENSWIFTUI_LIBRARY_TYPE": "dynamic",
            "OPENSWIFTUI_USE_LOCAL_DEPS": "1",
            "OTHER": "ignored",
        ])

        let result = await Environment.$additionalManifestEnvironmentKeys
            .withValue(["OPENSWIFTUI_LIBRARY_TYPE"]) {
                subject.manifestLoadingVariables
            }

        #expect(result["TUIST_FOO"] == "1")
        #expect(result["OPENSWIFTUI_LIBRARY_TYPE"] == "dynamic")
        #expect(result["OPENSWIFTUI_USE_LOCAL_DEPS"] == nil)
        #expect(result["OTHER"] == nil)
    }

    @Test() func manifestLoadingVariables_includesAdditionalKeysPrefixMatch() async throws {
        let subject = Environment(variables: [
            "OPENSWIFTUI_LIBRARY_TYPE": "dynamic",
            "OPENSWIFTUI_USE_LOCAL_DEPS": "1",
            "OPENSWIFTUI": "ignored",
            "OTHER": "ignored",
        ])

        let result = await Environment.$additionalManifestEnvironmentKeys
            .withValue(["OPENSWIFTUI_*"]) {
                subject.manifestLoadingVariables
            }

        #expect(result["OPENSWIFTUI_LIBRARY_TYPE"] == "dynamic")
        #expect(result["OPENSWIFTUI_USE_LOCAL_DEPS"] == "1")
        #expect(result["OPENSWIFTUI"] == nil)
        #expect(result["OTHER"] == nil)
    }
}
