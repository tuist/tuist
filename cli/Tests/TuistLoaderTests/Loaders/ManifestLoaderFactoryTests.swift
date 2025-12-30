import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistSupport

@testable import TuistLoader
@testable import TuistTesting

struct ManifestLoaderFactoryTests {
    func test_create_default_cached_manifest_loader() {
        // Given
        let sut = ManifestLoaderFactory()
        // When
        let result = sut.createManifestLoader()
        // Then
        #expect(type(of: result) is CachedManifestLoader.Type == true)
    }

    @Test(.withMockedEnvironment(
    )) func create_non_cached_manifest_loader_when_explicitely_configured_via_enviromentvariable(
    ) throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables[Constants.EnvironmentVariables.cacheManifests] = "0"
        let sut = ManifestLoaderFactory()
        // When
        let result = sut.createManifestLoader()
        // Then
        #expect(type(of: result) is ManifestLoader.Type == true)
    }

    @Test(.withMockedEnvironment()) func create_non_cached_manifest_loader_when_useCache_false() {
        // Given
        let sut = ManifestLoaderFactory(useCache: false)
        // When
        let result = sut.createManifestLoader()
        // Then
        #expect(type(of: result) is ManifestLoader.Type == true)
    }

    @Test(.withMockedEnvironment()) func create_cached_manifest_loader_when_useCache_true() {
        // Given
        let sut = ManifestLoaderFactory(useCache: true)
        // When
        let result = sut.createManifestLoader()
        // Then
        #expect(type(of: result) is CachedManifestLoader.Type == true)
    }
}
