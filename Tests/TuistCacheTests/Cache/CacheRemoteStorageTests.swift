import RxSwift
import TSCBasic
import TuistCacheTesting
import TuistCloud
import TuistCore
import TuistCoreTesting
import TuistSupport
import XCTest

@testable import TuistCache
@testable import TuistSupportTesting

final class CacheRemoteStorageTests: TuistUnitTestCase {
    var subject: CacheRemoteStorage!
    var cloudClient: CloudClienting!
    var config: Config!
    var fileArchiverFactory: MockFileArchiverFactory!
    var fileArchiver: MockFileArchiver!
    var fileClient: MockFileClient!
    var zipPath: AbsolutePath!

    override func setUp() {
        super.setUp()

        config = TuistCore.Config.test()
        zipPath = fixturePath(path: RelativePath("uUI.xcframework.zip"))

        fileArchiverFactory = MockFileArchiverFactory()
        fileArchiver = MockFileArchiver()
        fileArchiver.stubbedZipResult = zipPath
        fileArchiverFactory.stubbedMakeFileArchiverResult = fileArchiver
        fileClient = MockFileClient()
        fileClient.stubbedDownloadResult = Single.just(zipPath)

        let env = Environment.shared as! MockEnvironment
        env.cacheDirectoryStub = FileHandler.shared.currentPath.appending(component: "Cache")
    }

    override func tearDown() {
        config = nil
        subject = nil
        cloudClient = nil
        fileArchiver = nil
        fileArchiverFactory = nil
        fileClient = nil
        zipPath = nil
        super.tearDown()
    }

    // - exists

    func test_exists_whenClientReturnsAnError() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudHEADResponse>
        typealias ErrorType = CloudHEADResponseError
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForError(error: CloudHEADResponseError())
        subject = CacheRemoteStorage(cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        let result = subject.exists(hash: "acho tio", config: config)
            .toBlocking()
            .materialize()

        // Then
        switch result {
        case .completed:
            XCTFail("Expected result to complete with error, but result was successful.")
        case let .failed(_, error) where error is CloudHEADResponseError:
            XCTAssertEqual(error as! CloudHEADResponseError, CloudHEADResponseError())
        default:
            XCTFail("Expected result to complete with error, but result error wasn't the expected type.")
        }
    }

    func test_exists_whenClientReturnsAnHTTPError() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudHEADResponse>
        typealias ErrorType = CloudHEADResponseError
        let cloudResponse = ResponseType(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 500)
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        let result = try subject.exists(hash: "acho tio", config: config)
            .toBlocking()
            .single()

        // Then
        XCTAssertFalse(result)
    }

    func test_exists_whenClientReturnsASuccess() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudHEADResponse>
        typealias ErrorType = CloudHEADResponseError
        let cloudResponse = ResponseType(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test()
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        let result = try subject.exists(hash: "acho tio", config: config)
            .toBlocking()
            .single()

        // Then
        XCTAssertTrue(result)
    }

    func test_exists_whenClientReturnsA202() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudHEADResponse>
        typealias ErrorType = CloudHEADResponseError

        let cloudResponse = ResponseType(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 202)
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

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
        typealias ResponseType = CloudResponse<CloudCacheResponse>
        typealias ErrorType = CloudResponseError
        let expectedError: ErrorType = .test()
        let cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForError(error: expectedError)
        subject = CacheRemoteStorage(cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        let result = subject.fetch(hash: "acho tio", config: config)
            .toBlocking()
            .materialize()

        // Then
        switch result {
        case .completed:
            XCTFail("Expected result to complete with error, but result was successful.")
        case let .failed(_, error) where error is ErrorType:
            XCTAssertEqual(error as! ErrorType, expectedError)
        default:
            XCTFail("Expected result to complete with error, but result error wasn't the expected type.")
        }
    }

    func test_fetch_whenClientReturnsASuccess_returnsCorrectRootFolderAfterUnzipping() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudCacheResponse>
        typealias ErrorType = CloudResponseError

        let httpResponse: HTTPURLResponse = .test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        let hash = "acho tio"
        let paths = try createFolders(["Cache/xcframeworks/\(hash)/rootFolderAfterUnzipping"])

        // When
        let result = try subject.fetch(hash: hash, config: config)
            .toBlocking()
            .single()

        // Then
        XCTAssertEqual(result, paths.first!)
    }

    func test_fetch_whenClientReturnsASuccess_givesFileClientTheCorrectURL() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudCacheResponse>
        typealias ErrorType = CloudResponseError

        let httpResponse: HTTPURLResponse = .test()
        let url: URL = URL(string: "https://shaki.ra/acho/tio")!
        let cacheResponse = CloudCacheResponse(url: url, expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        let hash = "acho tio"
        _ = try createFolders(["Cache/xcframeworks/\(hash)/rootFolderAfterUnzipping"])

        // When
        _ = try subject.fetch(hash: hash, config: config)
            .toBlocking()
            .single()

        // Then
        XCTAssertEqual(fileClient.invokedDownloadParameters?.url, url)
    }

    func test_fetch_whenClientReturnsASuccess_givesFileArchiverTheCorrectDestinationPath() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudCacheResponse>
        typealias ErrorType = CloudResponseError

        let httpResponse: HTTPURLResponse = .test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        let hash = "acho tio"
        let paths = try createFolders(["Cache/xcframeworks/\(hash)/blah"])

        // When
        _ = try subject.fetch(hash: hash, config: config)
            .toBlocking()
            .single()

        // Then
        XCTAssertEqual(fileArchiver.invokedUnzipParameters?.to, paths.first!.parentDirectory)
    }

    // - store

    func test_store_whenClientReturnsAnError() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudCacheResponse>
        typealias ErrorType = CloudResponseError
        let expectedError = CloudResponseError.test()
        let cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForError(error: expectedError)

        subject = CacheRemoteStorage(cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        let result = subject.store(hash: "acho tio", config: config, xcframeworkPath: .root)
            .toBlocking()
            .materialize()

        // Then
        switch result {
        case .completed:
            XCTFail("Expected result to complete with error, but result was successful.")
        case let .failed(_, error) where error is CloudResponseError:
            XCTAssertEqual(error as! CloudResponseError, expectedError)
        default:
            XCTFail("Expected result to complete with error, but result error wasn't the expected type.")
        }
    }

    func test_store_whenClientReturnsASuccess_usesReturnedURLToUpload() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudCacheResponse>
        typealias ErrorType = CloudResponseError

        let url: URL = URL(string: "https://shaki.ra/acho/tio")!
        let cacheResponse = CloudCacheResponse(url: url, expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        let cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(
            object: cloudResponse,
            response: .test()
        )
        subject = CacheRemoteStorage(cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        _ = subject.store(hash: "acho tio", config: config, xcframeworkPath: .root)
            .toBlocking()
            .materialize()

        // Then
        if let tuple = fileClient.invokedUploadParameters {
            XCTAssertEqual(tuple.url, url)
        } else {
            XCTFail("Could not unwrap the file uploader input tuple")
        }
    }

    func test_store_whenClientReturnsASuccess_usesTheRightHashToUpload() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudCacheResponse>
        typealias ErrorType = CloudResponseError

        let hash = "acho tio hash"
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        let cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(
            object: cloudResponse,
            response: .test()
        )
        subject = CacheRemoteStorage(cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        _ = subject.store(hash: hash, config: config, xcframeworkPath: .root)
            .toBlocking()
            .materialize()

        // Then
        if let tuple = fileClient.invokedUploadParameters {
            XCTAssertEqual(tuple.hash, hash)
        } else {
            XCTFail("Could not unwrap the file uploader input tuple")
        }
    }

    func test_store_whenClientReturnsASuccess_usesTheRightZipPathToUpload() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudCacheResponse>
        typealias ErrorType = CloudResponseError

        let hash = "acho tio hash"
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        let cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(
            object: cloudResponse,
            response: .test()
        )

        fileArchiver.stubbedZipResult = zipPath
        subject = CacheRemoteStorage(cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        _ = subject.store(hash: hash, config: config, xcframeworkPath: .root)
            .toBlocking()
            .materialize()

        // Then
        if let tuple = fileClient.invokedUploadParameters {
            XCTAssertEqual(tuple.file, zipPath)
        } else {
            XCTFail("Could not unwrap the file uploader input tuple")
        }
    }
}
