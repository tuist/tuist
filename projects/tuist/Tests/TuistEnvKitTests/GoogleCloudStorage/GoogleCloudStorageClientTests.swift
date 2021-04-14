import RxBlocking
import struct TSCUtility.Version
import XCTest
@testable import TuistEnvKit
@testable import TuistSupportTesting

final class GoogleCloudStorageClientErrorTests: TuistUnitTestCase {
    func test_type_when_invalidEncoding() {
        // Given
        let url = URL.test()
        let subject = GoogleCloudStorageClientError.invalidEncoding(
            url: url,
            expectedEncoding: "utf8"
        )

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .bug)
    }

    func test_description_when_invalidEncoding() {
        // Given
        let url = URL.test()
        let subject = GoogleCloudStorageClientError.invalidEncoding(
            url: url,
            expectedEncoding: "utf8"
        )

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "Expected '\(url.absoluteString)' to have 'utf8' encoding")
    }

    func test_type_when_invalidVersionFormat() {
        // Given
        let subject = GoogleCloudStorageClientError.invalidVersionFormat("invalid")

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .bug)
    }

    func test_description_when_invalidVersionFormat() {
        // Given
        let subject = GoogleCloudStorageClientError.invalidVersionFormat("invalid")

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "Expected 'invalid' to follow the semver format")
    }
}

final class GoogleCloudStorageClientTests: TuistUnitTestCase {
    var scheduler: MockURLSessionScheduler!
    var subject: GoogleCloudStorageClient!

    override func setUp() {
        scheduler = MockURLSessionScheduler()
        subject = GoogleCloudStorageClient(urlSessionScheduler: scheduler)
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        scheduler = nil
        subject = nil
    }

    func test_latestVersion_errors_with_invalidVersionFormat_when_the_version_is_not_semver() throws {
        // Given
        let request = GoogleCloudStorageClient.releasesRequest(path: "latest/version")
        scheduler.stub(request: request, data: "invalid".description.data(using: .utf8)!)

        // Then
        XCTAssertThrowsSpecific(
            try subject.latestVersion().toBlocking().first(),
            GoogleCloudStorageClientError.invalidVersionFormat("invalid")
        )
    }

    func test_latestVersion_returns_the_version() throws {
        // Given
        let request = GoogleCloudStorageClient.releasesRequest(path: "latest/version")
        let version = Version(string: "3.2.1")!
        scheduler.stub(request: request, data: version.description.data(using: .utf8)!)

        // When
        let got = try subject.latestVersion().toBlocking().first()

        // Then
        XCTAssertNotNil(got)
        XCTAssertEqual(got, version)
    }

    func test_tuistBundleURL_when_a_release_exist() throws {
        // Given
        let version = "3.2.1"
        let releaseURL = GoogleCloudStorageClient.url(releasesPath: "\(version)/tuist.zip")
        var releaseRequest = URLRequest(url: releaseURL)
        releaseRequest.httpMethod = "HEAD"
        scheduler.stub(request: releaseRequest, data: Data())

        // When
        let got = try subject.tuistBundleURL(version: version).toBlocking().first()

        // Then
        XCTAssertEqual(got, releaseURL)
    }

    func test_tuistBundleURL_when_a_release_doesnt_exist_but_build_exists() throws {
        // Given
        let version = "3.2.1"

        let releaseURL = GoogleCloudStorageClient.url(releasesPath: "\(version)/tuist.zip")
        var releaseRequest = URLRequest(url: releaseURL)
        releaseRequest.httpMethod = "HEAD"

        let buildURL = GoogleCloudStorageClient.url(buildsPath: "\(version).zip")
        var buildRequest = URLRequest(url: buildURL)
        buildRequest.httpMethod = "HEAD"

        scheduler.stub(request: releaseRequest, error: URLError(.fileDoesNotExist))
        scheduler.stub(request: buildRequest, data: Data())

        // When
        let got = try subject.tuistBundleURL(version: version).toBlocking().first()

        // Then
        XCTAssertEqual(got, buildURL)
    }

    func test_tuistBundleURL_when_neither_the_release_nor_the_build_exist() throws {
        // Given
        let version = "3.2.1"

        let releaseURL = GoogleCloudStorageClient.url(releasesPath: "\(version)/tuist.zip")
        var releaseRequest = URLRequest(url: releaseURL)
        releaseRequest.httpMethod = "HEAD"

        let buildURL = GoogleCloudStorageClient.url(buildsPath: "\(version)/tuist.zip")
        var buildRequest = URLRequest(url: buildURL)
        buildRequest.httpMethod = "HEAD"

        scheduler.stub(request: releaseRequest, error: URLError(.fileDoesNotExist))
        scheduler.stub(request: buildRequest, error: URLError(.fileDoesNotExist))

        // When
        let got = try subject.tuistBundleURL(version: version).toBlocking().first()

        // Then
        XCTAssertNil(got ?? nil)
    }

    func test_latestTuistEnvBundleURL_returns_the_right_value() {
        // When
        let got = subject.latestTuistEnvBundleURL()

        // Then
        XCTAssertEqual(got, GoogleCloudStorageClient.url(releasesPath: "latest/tuistenv.zip"))
    }
}
