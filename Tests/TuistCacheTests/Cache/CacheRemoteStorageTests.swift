import RxSwift
import TSCBasic
import TuistCloud
import TuistCore
import TuistCoreTesting
import XCTest

@testable import TuistCache
@testable import TuistSupportTesting

final class CacheRemoteStorageTests: TuistUnitTestCase {
    var subject: CacheRemoteStorage!
    var cloudClient: CloudClienting!
    var config: Config!

    override func setUp() {
        super.setUp()
        config = TuistCore.Config.test()
    }

    override func tearDown() {
        config = nil
        subject = nil
        cloudClient = nil
        super.tearDown()
    }

    // - exists

    func test_exists_whenClientReturnsAnError() throws {
        // Given
        cloudClient = MockCloudClienting<CloudResponse<CloudHEADResponse>>.makeForError(error: CloudClientError.unauthorized)
        subject = CacheRemoteStorage(cloudClient: cloudClient)

        // When
        let result = subject.exists(hash: "acho tio", config: config)
            .toBlocking()
            .materialize()

        // Then
        switch result {
        case .completed:
            XCTFail("Expected result to complete with error, but result was successful.")
        case let .failed(_, error):
            XCTAssertEqual(error as! CloudClientError, CloudClientError.unauthorized)
        }
    }

    func test_exists_whenClientReturnsAnHTTPError() throws {
        // Given
        let cloudResponse = CloudResponse<CloudHEADResponse>(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 500)
        cloudClient = MockCloudClienting.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient)

        // When
        let result = try subject.exists(hash: "acho tio", config: config)
            .toBlocking()
            .single()

        // Then
        XCTAssertFalse(result)
    }

    func test_exists_whenClientReturnsASuccess() throws {
        // Given
        let cloudResponse = CloudResponse<CloudHEADResponse>(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test()
        cloudClient = MockCloudClienting.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient)

        // When
        let result = try subject.exists(hash: "acho tio", config: config)
            .toBlocking()
            .single()

        // Then
        XCTAssertTrue(result)
    }

    func test_exists_whenClientReturnsA202() throws {
        // Given
        let cloudResponse = CloudResponse<CloudHEADResponse>(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 202)
        cloudClient = MockCloudClienting.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient)

        // When
        let result = try subject.exists(hash: "acho tio", config: config)
            .toBlocking()
            .single()

        // Then
        XCTAssertTrue(result)
    }

    // - fetch

    func test_fetch_whenClientReturnsAnError() throws {
        // Given
        let cloudClient = MockCloudClienting<CloudResponse<CloudCacheResponse>>()
        cloudClient.configureForError(error: CloudClientError.unauthorized)
        subject = CacheRemoteStorage(cloudClient: cloudClient)

        // When
        let result = subject.fetch(hash: "acho tio", config: config)
            .toBlocking()
            .materialize()

        // Then
        switch result {
        case .completed:
            XCTFail("Expected result to complete with error, but result was successful.")
        case let .failed(_, error):
            XCTAssertEqual(error as! CloudClientError, CloudClientError.unauthorized)
        }
    }

    func test_fetch_whenClientReturnsASuccess() throws {
        // Given
        let httpResponse: HTTPURLResponse = .test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient = MockCloudClienting.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient)

        // When
        let result = try subject.fetch(hash: "acho tio", config: config)
            .toBlocking()
            .single()

        // Then
        XCTAssertEqual(result, AbsolutePath("/"))
    }

    // - store

    func test_store_whenClientReturnsAnError() throws {
        // Given
        let cloudClient = MockCloudClienting<CloudResponse<CloudCacheResponse>>()
        cloudClient.configureForError(error: CloudClientError.unauthorized)
        subject = CacheRemoteStorage(cloudClient: cloudClient)

        // When
        let result = subject.store(hash: "acho tio", config: config, xcframeworkPath: .root)
            .toBlocking()
            .materialize()

        // Then
        switch result {
        case .completed:
            XCTFail("Expected result to complete with error, but result was successful.")
        case let .failed(_, error):
            XCTAssertEqual(error as! CloudClientError, CloudClientError.unauthorized)
        }
    }
}
