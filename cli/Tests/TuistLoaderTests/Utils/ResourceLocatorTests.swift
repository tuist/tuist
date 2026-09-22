import Path
import Testing
import TuistEnvironment
@testable import TuistTesting

@testable import TuistLoader

struct ResourceLocatorTests {
    @Test(.withMockedEnvironment())
    func generatedProjectCASPluginCandidates_prefersTheInstalledCopy() throws {
        // Given
        let environment = try #require(Environment.mocked)

        // When
        let candidates = ResourceLocator.generatedProjectCASPluginCandidates()

        // Then
        #expect(candidates == [environment.casPluginInstallPath()] + ResourceLocator.casPluginCandidates())
    }

    /// A plugin built from source must reach generated projects directly, or rebuilding
    /// it would go unnoticed until `tuist setup cache` copied it again.
    @Test(.withMockedEnvironment())
    func generatedProjectCASPluginCandidates_whenOverridden_usesOnlyTheOverride() throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_CAS_PLUGIN_PATH"] = "/cas-plugin/target/release/libtuist_cas_plugin.dylib"

        // When
        let candidates = ResourceLocator.generatedProjectCASPluginCandidates()

        // Then
        #expect(candidates == [try AbsolutePath(validating: "/cas-plugin/target/release/libtuist_cas_plugin.dylib")])
    }

    /// `tuist setup cache` copies from `casPlugin()`. Resolving the installed copy there
    /// would copy it onto itself and never refresh it from a newer Tuist.
    @Test(.withMockedEnvironment())
    func casPluginCandidates_excludesTheInstalledCopy() throws {
        // Given
        let environment = try #require(Environment.mocked)

        // When
        let candidates = ResourceLocator.casPluginCandidates()

        // Then
        #expect(!candidates.contains(environment.casPluginInstallPath()))
    }
}
