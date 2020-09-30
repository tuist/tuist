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
    var fileArchiverFactory: MockFileArchivingFactory!
    var fileArchiver: MockFileArchiver!
    var fileUnarchiver: MockFileUnarchiver!
    var fileClient: MockFileClient!
    var zipPath: AbsolutePath!

    override func setUp() {
        super.setUp()

        config = TuistCore.Config.test()
        zipPath = fixturePath(path: RelativePath("uUI.xcframework.zip"))

        fileArchiverFactory = MockFileArchivingFactory()
        fileArchiver = MockFileArchiver()
        fileUnarchiver = MockFileUnarchiver()
        fileArchiver.stubbedZipResult = zipPath
        fileArchiverFactory.stubbedMakeFileArchiverResult = fileArchiver
        fileArchiverFactory.stubbedMakeFileUnarchiverResult = fileUnarchiver
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
        let config = Cloud.test()
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForError(error: CloudHEADResponseError())
        subject = CacheRemoteStorage(cloudConfig: config, cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        let result = subject.exists(hash: "acho tio")
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
        let CloudResponse = ResponseType(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 500)
        let config = Cloud.test()
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(object: CloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudConfig: config, cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        let result = try subject.exists(hash: "acho tio")
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
        let config = Cloud.test()
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudConfig: config, cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        let result = try subject.exists(hash: "acho tio")
            .toBlocking()
            .single()

        // Then
        XCTAssertTrue(result)
    }

    func test_exists_whenClientReturnsA202() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudHEADResponse>
        typealias ErrorType = CloudHEADResponseError

        let CloudResponse = ResponseType(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 202)
        let config = Cloud.test()
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(object: CloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudConfig: config, cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        let result = try subject.exists(hash: "acho tio")
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
        let config = Cloud.test()
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForError(error: expectedError)
        subject = CacheRemoteStorage(cloudConfig: config, cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        let result = subject.fetch(hash: "acho tio")
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

    func test_fetch_whenArchiveContainsIncorrectRootFolderAfterUnzipping_expectErrorThrown() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudCacheResponse>
        typealias ErrorType = CloudResponseError
        let httpResponse: HTTPURLResponse = .test()
        let config = Cloud.test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudConfig: config, cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        let hash = "foobar"
        let paths = try createFolders(["Unarchived/\(hash)/IncorrectRootFolderAfterUnzipping"])
        fileUnarchiver.stubbedUnzipResult = paths.first

        // When
        let result = subject.fetch(hash: hash)
            .toBlocking()
            .materialize()

        // Then
        switch result {
        case .completed:
            XCTFail("Expected result to complete with error, but result was successful.")
        case let .failed(_, error) where error is CacheRemoteStorageError:
            XCTAssertEqual(error as! CacheRemoteStorageError, CacheRemoteStorageError.frameworkNotFound(hash: hash))
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
        let config = Cloud.test()
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "success", data: cacheResponse)
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudConfig: config, cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        let hash = "bar_foo"
        let paths = try createFolders(["Unarchived/\(hash)/myFramework.xcframework"])
        fileUnarchiver.stubbedUnzipResult = paths.first?.parentDirectory

        // When
        let result = try subject.fetch(hash: hash)
            .toBlocking()
            .single()

        // Then
        let expectedPath = Environment.shared.buildCacheDirectory.appending(RelativePath("\(hash)/myFramework.xcframework"))
        XCTAssertEqual(result, expectedPath)
    }

    func test_fetch_whenClientReturnsASuccess_givesFileClientTheCorrectURL() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudCacheResponse>
        typealias ErrorType = CloudResponseError

        let httpResponse: HTTPURLResponse = .test()
        let url = URL(string: "https://tuist.io/acho/tio")!
        let config = Cloud.test()
        let cacheResponse = CloudCacheResponse(url: url, expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudConfig: config, cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        let hash = "foo_bar"
        let paths = try createFolders(["Unarchived/\(hash)/myFramework.xcframework"])
        fileUnarchiver.stubbedUnzipResult = paths.first!.parentDirectory

        // When
        _ = try subject.fetch(hash: hash)
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
        let config = Cloud.test()
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudConfig: config, cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        let paths = try createFolders(["Unarchived/\(hash)/Framework.framework"])
        fileUnarchiver.stubbedUnzipResult = paths.first?.parentDirectory

        let hash = "foo_bar"

        // When
        _ = try subject.fetch(hash: hash)
            .toBlocking()
            .single()

        // Then
        XCTAssertTrue(fileUnarchiver.invokedUnzip)
    }

    // - store

    func test_store_whenClientReturnsAnError() throws {
        // Given
        typealias ResponseType = CloudResponse<CloudCacheResponse>
        typealias ErrorType = CloudResponseError
        let expectedError = CloudResponseError.test()
        let config = Cloud.test()
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForError(error: expectedError)
        subject = CacheRemoteStorage(cloudConfig: config, cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        let result = subject.store(hash: "acho tio", paths: [.root])
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

        let url = URL(string: "https://shaki.ra/acho/tio")!
        let config = Cloud.test()
        let cacheResponse = CloudCacheResponse(url: url, expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(
            object: cloudResponse,
            response: .test()
        )
        subject = CacheRemoteStorage(cloudConfig: config, cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        _ = subject.store(hash: "foo_bar", paths: [.root])
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

        let hash = "foo_bar"
        let config = Cloud.test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(
            object: cloudResponse,
            response: .test()
        )
        subject = CacheRemoteStorage(cloudConfig: config, cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        _ = subject.store(hash: hash, paths: [.root])
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

        let hash = "foo_bar"
        let config = Cloud.test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "waka", data: cacheResponse)
        cloudClient = MockCloudClienting<ResponseType, ErrorType>.makeForSuccess(
            object: cloudResponse,
            response: .test()
        )

        fileArchiver.stubbedZipResult = zipPath
        subject = CacheRemoteStorage(cloudConfig: config, cloudClient: cloudClient, fileArchiverFactory: fileArchiverFactory, fileClient: fileClient)

        // When
        _ = subject.store(hash: hash, paths: [.root])
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
