import TuistCache
import TuistCloud
import TuistCloudTesting
import TuistCoreTesting
import TuistGraphTesting
import TuistSupportTesting
import XCTest
@testable import TuistKit

final class CacheStorageProviderTests: TuistUnitTestCase {
    private var subject: CacheStorageProvider!
    private var cacheDirectoryProviderFactory: MockCacheDirectoriesProviderFactory!
    private var cloudAuthenticationController: MockCloudAuthenticationController!

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheDirectoryProviderFactory = MockCacheDirectoriesProviderFactory(provider: try MockCacheDirectoriesProvider())
        cloudAuthenticationController = MockCloudAuthenticationController()
        subject = CacheStorageProvider(
            config: .test(),
            cacheDirectoryProviderFactory: cacheDirectoryProviderFactory,
            cloudAuthenticationController: cloudAuthenticationController
        )
    }

    override func tearDown() {
        cacheDirectoryProviderFactory = nil
        cloudAuthenticationController = nil
        subject = nil
        CacheStorageProvider.storages = nil
        super.tearDown()
    }

    func test_when_config_has_cloud_and_token() throws {
        // Given
        subject = CacheStorageProvider(
            config: .test(cloud: .test(options: [])),
            cacheDirectoryProviderFactory: cacheDirectoryProviderFactory,
            cloudAuthenticationController: cloudAuthenticationController
        )
        cloudAuthenticationController.authenticationTokenStub = { _ in
            "token"
        }

        // When
        let got = try subject.storages()

        // Then
        XCTAssertContainsElementOfType(got, CacheRemoteStorage.self)
        XCTAssertContainsElementOfType(got, CacheLocalStorage.self)
    }

    func test_when_config_has_cloud_and_no_token() throws {
        // Given
        subject = CacheStorageProvider(
            config: .test(cloud: .test(options: [])),
            cacheDirectoryProviderFactory: cacheDirectoryProviderFactory,
            cloudAuthenticationController: cloudAuthenticationController
        )
        cloudAuthenticationController.authenticationTokenStub = { _ in
            nil
        }

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.storages(),
            CacheStorageProviderError.tokenNotFound
        )
    }

    func test_when_config_has_optional_cloud_and_no_token() throws {
        // Given
        subject = CacheStorageProvider(
            config: .test(cloud: .test(options: [.optional])),
            cacheDirectoryProviderFactory: cacheDirectoryProviderFactory,
            cloudAuthenticationController: cloudAuthenticationController
        )
        cloudAuthenticationController.authenticationTokenStub = { _ in
            nil
        }

        // When
        let got = try subject.storages()

        // Then
        XCTAssertEqual(got.count, 1)
        XCTAssertContainsElementOfType(got, CacheLocalStorage.self)
        XCTAssertPrinterOutputContains(
            "Authentication token for tuist cloud was not found. Skipping using remote cache. Run `tuist cloud auth` to authenticate yourself."
        )
    }

    func test_when_config_is_without_cloud() throws {
        // Given
        subject = CacheStorageProvider(
            config: .test(cloud: nil),
            cacheDirectoryProviderFactory: cacheDirectoryProviderFactory,
            cloudAuthenticationController: cloudAuthenticationController
        )
        cloudAuthenticationController.authenticationTokenStub = { _ in
            nil
        }

        // When
        let got = try subject.storages()

        // Then
        XCTAssertEqual(got.count, 1)
        XCTAssertContainsElementOfType(got, CacheLocalStorage.self)
    }
}
