import RxSwift
import TSCBasic
import TuistCacheTesting
import TuistCloud
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest

@testable import TuistCache
@testable import TuistCacheTesting
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CacheRemoteStorageTests: TuistUnitTestCase {
    var subject: CacheRemoteStorage!
    var cloudClient: MockCloudClient!
    var fileArchiverFactory: MockFileArchivingFactory!
    var fileArchiver: MockFileArchiver!
    var fileUnarchiver: MockFileUnarchiver!
    var fileClient: MockFileClient!
    var zipPath: AbsolutePath!
    var mockCloudCacheResourceFactory: MockCloudCacheResourceFactory!
    let receivedUploadURL = URL(string: "https://remote.storage.com/upload")!
    var cacheDirectoriesProvider: MockCacheDirectoriesProvider!

    override func setUpWithError() throws {
        try super.setUpWithError()

        zipPath = fixturePath(path: RelativePath("uUI.xcframework.zip"))

        mockCloudCacheResourceFactory = MockCloudCacheResourceFactory()
        fileArchiverFactory = MockFileArchivingFactory()
        fileArchiver = MockFileArchiver()
        fileUnarchiver = MockFileUnarchiver()
        fileArchiver.stubbedZipResult = zipPath
        fileArchiverFactory.stubbedMakeFileArchiverResult = fileArchiver
        fileArchiverFactory.stubbedMakeFileUnarchiverResult = fileUnarchiver
        fileClient = MockFileClient()
        fileClient.stubbedDownloadResult = Single.just(zipPath)
        cloudClient = MockCloudClient()

        cacheDirectoriesProvider = try MockCacheDirectoriesProvider()
        cacheDirectoriesProvider.cacheDirectoryStub = try temporaryPath()

        subject = CacheRemoteStorage(
            cloudClient: cloudClient,
            fileArchiverFactory: fileArchiverFactory,
            fileClient: fileClient,
            cloudCacheResourceFactory: mockCloudCacheResourceFactory,
            cacheDirectoriesProvider: cacheDirectoriesProvider
        )
    }

    override func tearDown() {
        subject = nil
        cloudClient = nil
        fileArchiver = nil
        fileArchiverFactory = nil
        fileClient = nil
        zipPath = nil
        mockCloudCacheResourceFactory = nil
        cacheDirectoriesProvider = nil
        super.tearDown()
    }

    // - exists

    func test_exists_whenClientReturnsAnError() throws {
        // Given
        cloudClient.mock(error: CloudHEADResponseError())

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
        let cloudResponse: CloudResponse<CloudHEADResponse> = CloudResponse(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 500)
        cloudClient.mock(object: cloudResponse, response: httpResponse)

        // When
        let result = try subject.exists(hash: "acho tio")
            .toBlocking()
            .single()

        // Then
        XCTAssertFalse(result)
    }

    func test_exists_whenClientReturnsASuccess() throws {
        // Given
        let cloudResponse = CloudResponse<CloudHEADResponse>(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test()
        cloudClient.mock(object: cloudResponse, response: httpResponse)

        // When
        let result = try subject.exists(hash: "acho tio")
            .toBlocking()
            .single()

        // Then
        XCTAssertTrue(result)
    }

    func test_exists_whenClientReturnsA202() throws {
        // Given
        let cloudResponse = CloudResponse<CloudHEADResponse>(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 202)
        cloudClient.mock(object: cloudResponse, response: httpResponse)

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
        let expectedError: CloudResponseError = .test()
        cloudClient.mock(error: expectedError)

        // When
        let result = subject.fetch(hash: "acho tio")
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

    func test_fetch_whenArchiveContainsIncorrectRootFolderAfterUnzipping_expectErrorThrown() throws {
        // Given
        let httpResponse: HTTPURLResponse = .test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient.mock(object: cloudResponse, response: httpResponse)

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
            XCTAssertEqual(error as! CacheRemoteStorageError, CacheRemoteStorageError.artifactNotFound(hash: hash))
        default:
            XCTFail("Expected result to complete with error, but result error wasn't the expected type.")
        }
    }

    func test_fetch_whenClientReturnsASuccess_returnsCorrectRootFolderAfterUnzipping() throws {
        // Given
        let httpResponse: HTTPURLResponse = .test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "success", data: cacheResponse)
        cloudClient.mock(object: cloudResponse, response: httpResponse)

        let hash = "bar_foo"
        let paths = try createFolders(["Unarchived/\(hash)/myFramework.xcframework"])
        fileUnarchiver.stubbedUnzipResult = paths.first?.parentDirectory

        // When
        let result = try subject.fetch(hash: hash)
            .toBlocking()
            .single()

        // Then
        let expectedPath = cacheDirectoriesProvider.cacheDirectory(for: .builds).appending(RelativePath("\(hash)/myFramework.xcframework"))
        XCTAssertEqual(result, expectedPath)
    }

    func test_fetch_whenClientReturnsASuccess_givesFileClientTheCorrectURL() throws {
        // Given
        let httpResponse: HTTPURLResponse = .test()
        let url = URL(string: "https://tuist.io/acho/tio")!
        let cacheResponse = CloudCacheResponse(url: url, expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient.mock(object: cloudResponse, response: httpResponse)

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
        let httpResponse: HTTPURLResponse = .test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient.mock(object: cloudResponse, response: httpResponse)

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
        let expectedError = CloudResponseError.test()
        cloudClient.mock(error: expectedError)

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

    func test_store_whenClientReturnsASuccess_returnsURLToUpload() throws {
        // Given
        configureCloudClientForSuccessfulUpload()

        // When
        _ = subject.store(hash: "foo_bar", paths: [.root])
            .toBlocking()
            .materialize()

        // Then
        if let tuple = fileClient.invokedUploadParameters {
            XCTAssertEqual(tuple.url, receivedUploadURL)
        } else {
            XCTFail("Could not unwrap the file uploader input tuple")
        }
    }

    func test_store_whenClientReturnsASuccess_usesTheRightHashToUpload() throws {
        // Given
        let hash = "foo_bar"
        configureCloudClientForSuccessfulUpload()

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
        let hash = "foo_bar"
        configureCloudClientForSuccessfulUpload()
        fileArchiver.stubbedZipResult = zipPath

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

    func test_store_whenClientReturnsAnUploadErrorVerifyIsNotCalled() throws {
        // Given
        let expectedError = CloudResponseError.test()
        cloudClient.mock(error: expectedError)

        // When
        _ = subject.store(hash: "acho tio", paths: [.root])
            .toBlocking()
            .materialize()

        // Then
        XCTAssertFalse(mockCloudCacheResourceFactory.invokedVerifyUploadResource)
    }

    func test_store_whenFileUploaderReturnsAnErrorFileArchiverIsCalled() throws {
        // Given
        configureCloudClientForSuccessfulUpload()
        fileClient.stubbedUploadResult = Single.error(TestError("Error uploading file"))

        // When
        _ = subject.store(hash: "acho tio", paths: [.root])
            .toBlocking()
            .materialize()

        // Then
        XCTAssertEqual(fileArchiver.invokedDeleteCount, 1)
    }

    func test_store_whenFileUploaderReturnsAnErrorVerifyIsNotCalled() throws {
        // Given
        configureCloudClientForSuccessfulUpload()
        fileClient.stubbedUploadResult = Single.error(TestError("Error uploading file"))

        // When
        _ = subject.store(hash: "acho tio", paths: [.root])
            .toBlocking()
            .materialize()

        // Then
        XCTAssertFalse(mockCloudCacheResourceFactory.invokedVerifyUploadResource)
    }

    func test_store_whenVerifyFailsTheZipArchiveIsDeleted() throws {
        // Given
        configureCloudClientForSuccessfulUploadAndFailedVerify()

        // When
        _ = subject.store(hash: "verify fails hash", paths: [.root])
            .toBlocking()
            .materialize()

        // Then
        XCTAssertEqual(fileArchiver.invokedDeleteCount, 1)
    }

    // MARK: Private

    private func configureCloudClientForSuccessfulUpload() {
        let uploadURLRequest = URLRequest.test(urlString: "https://tuist.cache.io/store")
        let verifyUploadURLRequest = URLRequest.test(urlString: "https://tuist.cache.io/verify-upload")

        let receivedUploadURLRequest = URLRequest.test(url: receivedUploadURL)
        let cacheResponse = CloudCacheResponse(url: receivedUploadURLRequest.url!, expiresAt: 123)
        let uploadURLObject = CloudResponse<CloudCacheResponse>(status: "uploadURLObject status", data: cacheResponse)

        let cloudVerifyUploadResponse = CloudVerifyUploadResponse.test()
        let verifyUploadObject = CloudResponse<CloudVerifyUploadResponse>(status: "cloudVerifyUploadResponse status", data: cloudVerifyUploadResponse)

        cloudClient.mock(objectPerURLRequest: [
            uploadURLRequest: uploadURLObject,
            verifyUploadURLRequest: verifyUploadObject,
        ])

        mockCloudCacheResourceFactory.stubbedStoreResourceResult = HTTPResource(
            request: { uploadURLRequest },
            parse: { _, _ in uploadURLObject },
            parseError: { _, _ in CloudResponseError.test() }
        )

        mockCloudCacheResourceFactory.stubbedVerifyUploadResourceResult = HTTPResource(
            request: { verifyUploadURLRequest },
            parse: { _, _ in verifyUploadObject },
            parseError: { _, _ in CloudResponseError.test() }
        )
    }

    private func configureCloudClientForSuccessfulUploadAndFailedVerify() {
        let uploadURLRequest = URLRequest.test(urlString: "https://tuist.cache.io/store")
        let verifyUploadURLRequest = URLRequest.test(urlString: "https://tuist.cache.io/verify-upload")

        let receivedUploadURLRequest = URLRequest.test(url: receivedUploadURL)
        let cacheResponse = CloudCacheResponse(url: receivedUploadURLRequest.url!, expiresAt: 123)
        let uploadURLObject = CloudResponse<CloudCacheResponse>(status: "uploadURLObject status", data: cacheResponse)

        let cloudVerifyUploadResponse = CloudVerifyUploadResponse.test()
        let verifyUploadObject = CloudResponse<CloudVerifyUploadResponse>(status: "cloudVerifyUploadResponse status", data: cloudVerifyUploadResponse)
        let verifyUploadError = CloudResponseError.test()

        cloudClient.mock(
            objectPerURLRequest: [uploadURLRequest: uploadURLObject],
            errorPerURLRequest: [verifyUploadURLRequest: verifyUploadError]
        )

        mockCloudCacheResourceFactory.stubbedStoreResourceResult = HTTPResource(
            request: { uploadURLRequest },
            parse: { _, _ in uploadURLObject },
            parseError: { _, _ in CloudResponseError.test() }
        )

        mockCloudCacheResourceFactory.stubbedVerifyUploadResourceResult = HTTPResource(
            request: { verifyUploadURLRequest },
            parse: { _, _ in verifyUploadObject },
            parseError: { _, _ in verifyUploadError }
        )
    }
}
