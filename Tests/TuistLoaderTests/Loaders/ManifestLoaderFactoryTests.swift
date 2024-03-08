import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class ManifestLoaderFactoryTests: TuistUnitTestCase {
    var context: MockContext!
    
    override func setUp() {
        super.setUp()
        context = MockContext()
    }
    
    override func tearDown() {
        context = nil
        super.tearDown()
    }
    
    func test_create_default_cached_manifest_loader() {
        // Given
        let sut = ManifestLoaderFactory()
        // When
        let result = sut.createManifestLoader(context: context)
        // Then
        XCTAssert(type(of: result) is CachedManifestLoader.Type)
    }

    func test_create_non_cached_manifest_loader_when_explicitely_configured_via_enviromentvariable() {
        // Given
        context.mockEnvironment.useManifestsCache = false
        let sut = ManifestLoaderFactory()
        
        // When
        let result = sut.createManifestLoader(context: context)
        // Then
        XCTAssert(type(of: result) is ManifestLoader.Type)
    }

    func test_create_non_cached_manifest_loader_when_useCache_false() {
        // Given
        let sut = ManifestLoaderFactory()
        context.mockEnvironment.useManifestsCache = false
        
        // When
        let result = sut.createManifestLoader(context: context)
        // Then
        XCTAssert(type(of: result) is ManifestLoader.Type)
    }

    func test_create_cached_manifest_loader_when_useCache_true() {
        // Given
        let sut = ManifestLoaderFactory()
        context.mockEnvironment.useManifestsCache = true
        
        // When
        let result = sut.createManifestLoader(context: context)
        
        // Then
        XCTAssert(type(of: result) is CachedManifestLoader.Type)
    }
}
