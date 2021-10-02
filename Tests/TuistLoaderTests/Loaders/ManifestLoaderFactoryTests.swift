import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class ManifestLoaderFactoryTests: TuistUnitTestCase {
    func test_create_default_cached_manifest_loader() {
        // Given
        let sut = ManifestLoaderFactory()
        // When
        let result = sut.createManifestLoader()
        // Then
        XCTAssert(type(of: result) is CachedManifestLoader.Type)
    }

    func test_create_non_cached_manifest_loader_when_explicitely_configured_via_enviromentvariable() {
        // Given
        environment.tuistConfigVariables[Constants.EnvironmentVariables.cacheManifests] = "0"
        let sut = ManifestLoaderFactory()
        // When
        let result = sut.createManifestLoader()
        // Then
        XCTAssert(type(of: result) is ManifestLoader.Type)
    }

    func test_create_non_cached_manifest_loader_when_useCache_false() {
        // Given
        let sut = ManifestLoaderFactory(useCache: false)
        // When
        let result = sut.createManifestLoader()
        // Then
        XCTAssert(type(of: result) is ManifestLoader.Type)
    }

    func test_create_cached_manifest_loader_when_useCache_true() {
        // Given
        let sut = ManifestLoaderFactory(useCache: true)
        // When
        let result = sut.createManifestLoader()
        // Then
        XCTAssert(type(of: result) is CachedManifestLoader.Type)
    }
}
