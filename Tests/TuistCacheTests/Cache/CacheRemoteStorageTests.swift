import RxSwift
import TSCBasic
import TuistCacheTesting
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistLab
import TuistSupport
import XCTest

@testable import TuistCache
@testable import TuistCacheTesting
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CacheRemoteStorageTests: TuistUnitTestCase {
    var subject: CacheRemoteStorage!
    var labClient: MockLabClient!
    var fileArchiverFactory: MockFileArchivingFactory!
    var fileArchiver: MockFileArchiver!
    var fileUnarchiver: MockFileUnarchiver!
    var fileClient: MockFileClient!
    var zipPath: AbsolutePath!
    var mockLabCacheResourceFactory: MockLabCacheResourceFactory!
    let receivedUploadURL = URL(string: "https://remote.storage.com/upload")!
    var cacheDirectoriesProvider: MockCacheDirectoriesProvider!

    override func setUpWithError() throws {
        try super.setUpWithError()

        zipPath = fixturePath(path: RelativePath("uUI.xcframework.zip"))

        mockLabCacheResourceFactory = MockLabCacheResourceFactory()
        fileArchiverFactory = MockFileArchivingFactory()
        fileArchiver = MockFileArchiver()
        fileUnarchiver = MockFileUnarchiver()
        fileArchiver.stubbedZipResult = zipPath
        fileArchiverFactory.stubbedMakeFileArchiverResult = fileArchiver
        fileArchiverFactory.stubbedMakeFileUnarchiverResult = fileUnarchiver
        fileClient = MockFileClient()
        fileClient.stubbedDownloadResult = Single.just(zipPath)
        labClient = MockLabClient()

        cacheDirectoriesProvider = try MockCacheDirectoriesProvider()
        cacheDirectoriesProvider.cacheDirectoryStub = try temporaryPath()

        subject = CacheRemoteStorage(
            labClient: labClient,
            fileArchiverFactory: fileArchiverFactory,
            fileClient: fileClient,
            labCacheResourceFactory: mockLabCacheResourceFactory,
            cacheDirectoriesProvider: cacheDirectoriesProvider
        )
    }

    override func tearDown() {
        subject = nil
        labClient = nil
        fileArchiver = nil
        fileArchiverFactory = nil
        fileClient = nil
        zipPath = nil
        mockLabCacheResourceFactory = nil
        cacheDirectoriesProvider = nil
        super.tearDown()
    }

    // - exists

    func test_exists_whenClientReturnsAnError() throws {
        // Given
        labClient.mock(error: LabHEADResponseError())

        // When
        let result = subject.exists(hash: "acho tio")
            .toBlocking()
            .materialize()

        // Then
        switch result {
        case .completed:
            XCTFail("Expected result to complete with error, but result was successful.")
        case let .failed(_, error) where error is LabHEADResponseError:
            XCTAssertEqual(error as! LabHEADResponseError, LabHEADResponseError())
        default:
            XCTFail("Expected result to complete with error, but result error wasn't the expected type.")
        }
    }

    func test_exists_whenClientReturnsAnHTTPError() throws {
        // Given
        let labResponse: LabResponse<LabHEADResponse> = LabResponse(status: "shaki", data: LabHEADResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 500)
        labClient.mock(object: labResponse, response: httpResponse)

        // When
        let result = try subject.exists(hash: "acho tio")
            .toBlocking()
            .single()

        // Then
        XCTAssertFalse(result)
    }

    func test_exists_whenClientReturnsASuccess() throws {
        // Given
        let labResponse = LabResponse<LabHEADResponse>(status: "shaki", data: LabHEADResponse())
        let httpResponse: HTTPURLResponse = .test()
        labClient.mock(object: labResponse, response: httpResponse)

        // When
        let result = try subject.exists(hash: "acho tio")
            .toBlocking()
            .single()

        // Then
        XCTAssertTrue(result)
    }

    func test_exists_whenClientReturnsA202() throws {
        // Given
        let labResponse = LabResponse<LabHEADResponse>(status: "shaki", data: LabHEADResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 202)
        labClient.mock(object: labResponse, response: httpResponse)

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
        let expectedError: LabResponseError = .test()
        labClient.mock(error: expectedError)

        // When
        let result = subject.fetch(hash: "acho tio")
            .toBlocking()
            .materialize()

        // Then
        switch result {
        case .completed:
            XCTFail("Expected result to complete with error, but result was successful.")
        case let .failed(_, error) where error is LabResponseError:
            XCTAssertEqual(error as! LabResponseError, expectedError)
        default:
            XCTFail("Expected result to complete with error, but result error wasn't the expected type.")
        }
    }

    func test_fetch_whenArchiveContainsIncorrectRootFolderAfterUnzipping_expectErrorThrown() throws {
        // Given
        let httpResponse: HTTPURLResponse = .test()
        let cacheResponse = LabCacheResponse(url: .test(), expiresAt: 123)
        let labResponse = LabResponse<LabCacheResponse>(status: "shaki", data: cacheResponse)
        labClient.mock(object: labResponse, response: httpResponse)

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
        let httpResponse: HTTPURLResponse = .test()
        let cacheResponse = LabCacheResponse(url: .test(), expiresAt: 123)
        let labResponse = LabResponse<LabCacheResponse>(status: "success", data: cacheResponse)
        labClient.mock(object: labResponse, response: httpResponse)

        let hash = "bar_foo"
        let paths = try createFolders(["Unarchived/\(hash)/myFramework.xcframework"])
        fileUnarchiver.stubbedUnzipResult = paths.first?.parentDirectory

        // When
        let result = try subject.fetch(hash: hash)
            .toBlocking()
            .single()

        // Then
        let expectedPath = cacheDirectoriesProvider.buildCacheDirectory.appending(RelativePath("\(hash)/myFramework.xcframework"))
        XCTAssertEqual(result, expectedPath)
    }

    func test_fetch_whenClientReturnsASuccess_givesFileClientTheCorrectURL() throws {
        // Given
        let httpResponse: HTTPURLResponse = .test()
        let url = URL(string: "https://tuist.io/acho/tio")!
        let cacheResponse = LabCacheResponse(url: url, expiresAt: 123)
        let labResponse = LabResponse<LabCacheResponse>(status: "shaki", data: cacheResponse)
        labClient.mock(object: labResponse, response: httpResponse)

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
        let cacheResponse = LabCacheResponse(url: .test(), expiresAt: 123)
        let labResponse = LabResponse<LabCacheResponse>(status: "shaki", data: cacheResponse)
        labClient.mock(object: labResponse, response: httpResponse)

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
        let expectedError = LabResponseError.test()
        labClient.mock(error: expectedError)

        // When
        let result = subject.store(hash: "acho tio", paths: [.root])
            .toBlocking()
            .materialize()

        // Then
        switch result {
        case .completed:
            XCTFail("Expected result to complete with error, but result was successful.")
        case let .failed(_, error) where error is LabResponseError:
            XCTAssertEqual(error as! LabResponseError, expectedError)
        default:
            XCTFail("Expected result to complete with error, but result error wasn't the expected type.")
        }
    }

    func test_store_whenClientReturnsASuccess_returnsURLToUpload() throws {
        // Given
        configureLabClientForSuccessfulUpload()

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
        configureLabClientForSuccessfulUpload()

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
        configureLabClientForSuccessfulUpload()
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
        let expectedError = LabResponseError.test()
        labClient.mock(error: expectedError)

        // When
        _ = subject.store(hash: "acho tio", paths: [.root])
            .toBlocking()
            .materialize()

        // Then
        XCTAssertFalse(mockLabCacheResourceFactory.invokedVerifyUploadResource)
    }

    func test_store_whenFileUploaderReturnsAnErrorFileArchiverIsCalled() throws {
        // Given
        configureLabClientForSuccessfulUpload()
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
        configureLabClientForSuccessfulUpload()
        fileClient.stubbedUploadResult = Single.error(TestError("Error uploading file"))

        // When
        _ = subject.store(hash: "acho tio", paths: [.root])
            .toBlocking()
            .materialize()

        // Then
        XCTAssertFalse(mockLabCacheResourceFactory.invokedVerifyUploadResource)
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

    private func configureLabClientForSuccessfulUpload() {
        let uploadURLRequest = URLRequest.test(urlString: "https://tuist.cache.io/store")
        let verifyUploadURLRequest = URLRequest.test(urlString: "https://tuist.cache.io/verify-upload")

        let receivedUploadURLRequest = URLRequest.test(url: receivedUploadURL)
        let cacheResponse = LabCacheResponse(url: receivedUploadURLRequest.url!, expiresAt: 123)
        let uploadURLObject = LabResponse<LabCacheResponse>(status: "uploadURLObject status", data: cacheResponse)

        let cloudVerifyUploadResponse = LabVerifyUploadResponse.test()
        let verifyUploadObject = LabResponse<LabVerifyUploadResponse>(status: "cloudVerifyUploadResponse status", data: cloudVerifyUploadResponse)

        labClient.mock(objectPerURLRequest: [
            uploadURLRequest: uploadURLObject,
            verifyUploadURLRequest: verifyUploadObject,
        ])

        mockLabCacheResourceFactory.stubbedStoreResourceResult = HTTPResource(
            request: { uploadURLRequest },
            parse: { _, _ in uploadURLObject },
            parseError: { _, _ in LabResponseError.test() }
        )

        mockLabCacheResourceFactory.stubbedVerifyUploadResourceResult = HTTPResource(
            request: { verifyUploadURLRequest },
            parse: { _, _ in verifyUploadObject },
            parseError: { _, _ in LabResponseError.test() }
        )
    }

    private func configureCloudClientForSuccessfulUploadAndFailedVerify() {
        let uploadURLRequest = URLRequest.test(urlString: "https://tuist.cache.io/store")
        let verifyUploadURLRequest = URLRequest.test(urlString: "https://tuist.cache.io/verify-upload")

        let receivedUploadURLRequest = URLRequest.test(url: receivedUploadURL)
        let cacheResponse = LabCacheResponse(url: receivedUploadURLRequest.url!, expiresAt: 123)
        let uploadURLObject = LabResponse<LabCacheResponse>(status: "uploadURLObject status", data: cacheResponse)

        let cloudVerifyUploadResponse = LabVerifyUploadResponse.test()
        let verifyUploadObject = LabResponse<LabVerifyUploadResponse>(status: "cloudVerifyUploadResponse status", data: cloudVerifyUploadResponse)
        let verifyUploadError = LabResponseError.test()

        labClient.mock(
            objectPerURLRequest: [uploadURLRequest: uploadURLObject],
            errorPerURLRequest: [verifyUploadURLRequest: verifyUploadError]
        )

        mockLabCacheResourceFactory.stubbedStoreResourceResult = HTTPResource(
            request: { uploadURLRequest },
            parse: { _, _ in uploadURLObject },
            parseError: { _, _ in LabResponseError.test() }
        )

        mockLabCacheResourceFactory.stubbedVerifyUploadResourceResult = HTTPResource(
            request: { verifyUploadURLRequest },
            parse: { _, _ in verifyUploadObject },
            parseError: { _, _ in verifyUploadError }
        )
    }
}
