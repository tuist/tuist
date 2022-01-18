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
        fileClient.stubbedDownloadResult = zipPath
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

    func test_exists_whenClientReturnsAnError() async throws {
        // Given
        cloudClient.mock(error: CloudEmptyResponseError())

        // When
        do {
            _ = try await subject.exists(name: "targetName", hash: "acho tio")
            XCTFail("Expected result to complete with error, but result was successful.")
        } catch {
            // Then
            if error is CloudEmptyResponseError {
                XCTAssertEqual(error as! CloudEmptyResponseError, CloudEmptyResponseError())
            } else {
                XCTFail("Expected result to complete with error, but result error wasn't the expected type.")
            }
        }
    }

    func test_exists_whenClientReturnsAnHTTPError() async throws {
        // Given
        let cloudResponse: CloudResponse<CloudEmptyResponse> = CloudResponse(status: "shaki", data: CloudEmptyResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 500)
        cloudClient.mock(object: cloudResponse, response: httpResponse)

        // When
        let result = try await subject.exists(name: "targetName", hash: "acho tio")

        // Then
        XCTAssertFalse(result)
    }

    func test_exists_whenClientReturnsASuccess() async throws {
        // Given
        let cloudResponse = CloudResponse<CloudEmptyResponse>(status: "shaki", data: CloudEmptyResponse())
        let httpResponse: HTTPURLResponse = .test()
        cloudClient.mock(object: cloudResponse, response: httpResponse)

        // When
        let result = try await subject.exists(name: "targetName", hash: "acho tio")

        // Then
        XCTAssertTrue(result)
    }

    func test_exists_whenClientReturnsA202() async throws {
        // Given
        let cloudResponse = CloudResponse<CloudEmptyResponse>(status: "shaki", data: CloudEmptyResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 202)
        cloudClient.mock(object: cloudResponse, response: httpResponse)

        // When
        let result = try await subject.exists(name: "targetName", hash: "acho tio")

        // Then
        XCTAssertTrue(result)
    }

    // - fetch

    func test_fetch_whenClientReturnsAnError() async throws {
        // Given
        let expectedError: CloudResponseError = .test()
        cloudClient.mock(error: expectedError)

        do {
            // When
            _ = try await subject.fetch(name: "targetName", hash: "acho tio")
            XCTFail("Expected result to complete with error, but result was successful.")
        } catch {
            // Then
            if error is CloudResponseError {
                XCTAssertEqual(error as! CloudResponseError, expectedError)
            } else {
                XCTFail("Expected result to complete with error, but result error wasn't the expected type.")
            }
        }
    }

    func test_fetch_whenArchiveContainsIncorrectRootFolderAfterUnzipping_expectErrorThrown() async throws {
        // Given
        let httpResponse: HTTPURLResponse = .test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient.mock(object: cloudResponse, response: httpResponse)

        let hash = "foobar"
        let paths = try createFolders(["Unarchived/\(hash)/IncorrectRootFolderAfterUnzipping"])
        fileUnarchiver.stubbedUnzipResult = paths.first

        do {
            // When
            _ = try await subject.fetch(name: "targetName", hash: hash)
            XCTFail("Expected result to complete with error, but result was successful.")
        } catch {
            // Then
            if error is CacheRemoteStorageError {
                XCTAssertEqual(error as! CacheRemoteStorageError, CacheRemoteStorageError.artifactNotFound(hash: hash))
            } else {
                XCTFail("Expected result to complete with error, but result error wasn't the expected type.")
            }
        }
    }

    func test_fetch_whenClientReturnsASuccess_returnsCorrectRootFolderAfterUnzipping() async throws {
        // Given
        let httpResponse: HTTPURLResponse = .test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "success", data: cacheResponse)
        cloudClient.mock(object: cloudResponse, response: httpResponse)

        let hash = "bar_foo"
        let paths = try createFolders(["Unarchived/\(hash)/myFramework.xcframework"])
        fileUnarchiver.stubbedUnzipResult = paths.first?.parentDirectory

        // When
        let result = try await subject.fetch(name: "targetName", hash: hash)

        // Then
        let expectedPath = cacheDirectoriesProvider.cacheDirectory(for: .builds)
            .appending(RelativePath("\(hash)/myFramework.xcframework"))
        XCTAssertEqual(result, expectedPath)
    }

    func test_fetch_whenClientReturnsASuccess_givesFileClientTheCorrectURL() async throws {
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
        _ = try await subject.fetch(name: "targetName", hash: hash)

        // Then
        XCTAssertEqual(fileClient.invokedDownloadParameters?.url, url)
    }

    func test_fetch_whenClientReturnsASuccess_givesFileArchiverTheCorrectDestinationPath() async throws {
        // Given
        let httpResponse: HTTPURLResponse = .test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient.mock(object: cloudResponse, response: httpResponse)

        let paths = try createFolders(["Unarchived/\(hash)/Framework.framework"])
        fileUnarchiver.stubbedUnzipResult = paths.first?.parentDirectory

        let hash = "foo_bar"

        // When
        _ = try await subject.fetch(name: "targetName", hash: hash)

        // Then
        XCTAssertTrue(fileUnarchiver.invokedUnzip)
    }

    // - store

    func test_store_whenClientReturnsAnError() async throws {
        // Given
        let expectedError = CloudResponseError.test()
        cloudClient.mock(error: expectedError)

        do {
            // When
            _ = try await subject.store(name: "targetName", hash: "acho tio", paths: [.root])
            XCTFail("Expected result to complete with error, but result was successful.")
        } catch {
            // Then
            if error is CloudResponseError {
                XCTAssertEqual(error as! CloudResponseError, expectedError)
            } else {
                XCTFail("Expected result to complete with error, but result error wasn't the expected type.")
            }
        }
    }

    func test_store_whenClientReturnsASuccess_returnsURLToUpload() async throws {
        // Given
        configureCloudClientForSuccessfulUpload()

        // When
        _ = try await subject.store(name: "targetName", hash: "foo_bar", paths: [.root])

        // Then
        if let tuple = fileClient.invokedUploadParameters {
            XCTAssertEqual(tuple.url, receivedUploadURL)
        } else {
            XCTFail("Could not unwrap the file uploader input tuple")
        }
    }

    func test_store_whenClientReturnsASuccess_usesTheRightHashToUpload() async throws {
        // Given
        let hash = "foo_bar"
        configureCloudClientForSuccessfulUpload()

        // When
        _ = try await subject.store(name: "targetName", hash: hash, paths: [.root])

        // Then
        if let tuple = fileClient.invokedUploadParameters {
            XCTAssertEqual(tuple.hash, hash)
        } else {
            XCTFail("Could not unwrap the file uploader input tuple")
        }
    }

    func test_store_whenClientReturnsASuccess_usesTheRightZipPathToUpload() async throws {
        // Given
        let hash = "foo_bar"
        configureCloudClientForSuccessfulUpload()
        fileArchiver.stubbedZipResult = zipPath

        // When
        _ = try await subject.store(name: "targetName", hash: hash, paths: [.root])

        // Then
        if let tuple = fileClient.invokedUploadParameters {
            XCTAssertEqual(tuple.file, zipPath)
        } else {
            XCTFail("Could not unwrap the file uploader input tuple")
        }
    }

    func test_store_whenClientReturnsAnUploadErrorVerifyIsNotCalled() async throws {
        // Given
        let expectedError = CloudResponseError.test()
        cloudClient.mock(error: expectedError)

        // When
        _ = try? await subject.store(name: "targetName", hash: "acho tio", paths: [.root])

        // Then
        XCTAssertFalse(mockCloudCacheResourceFactory.invokedVerifyUploadResource)
    }

    func test_store_whenFileUploaderReturnsAnErrorFileArchiverIsCalled() async throws {
        // Given
        configureCloudClientForSuccessfulUpload()
        fileClient.stubbedUploadError = TestError("Error uploading file")

        // When
        _ = try? await subject.store(name: "targetName", hash: "acho tio", paths: [.root])

        // Then
        XCTAssertEqual(fileArchiver.invokedDeleteCount, 1)
    }

    func test_store_whenFileUploaderReturnsAnErrorVerifyIsNotCalled() async throws {
        // Given
        configureCloudClientForSuccessfulUpload()
        fileClient.stubbedUploadError = TestError("Error uploading file")

        // When
        _ = try? await subject.store(name: "targetName", hash: "acho tio", paths: [.root])

        // Then
        XCTAssertFalse(mockCloudCacheResourceFactory.invokedVerifyUploadResource)
    }

    func test_store_whenVerifyFailsTheZipArchiveIsDeleted() async throws {
        // Given
        configureCloudClientForSuccessfulUploadAndFailedVerify()

        // When
        _ = try? await subject.store(name: "targetName", hash: "verify fails hash", paths: [.root])

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
        let verifyUploadObject = CloudResponse<CloudVerifyUploadResponse>(
            status: "cloudVerifyUploadResponse status",
            data: cloudVerifyUploadResponse
        )

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
        let verifyUploadObject = CloudResponse<CloudVerifyUploadResponse>(
            status: "cloudVerifyUploadResponse status",
            data: cloudVerifyUploadResponse
        )
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
