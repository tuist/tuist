import RxBlocking
import SPMUtility
import XCTest
@testable import TuistEnvKit
@testable import TuistSupportTesting

final class GoogleCloudStorageClientErrorTests: TuistUnitTestCase {
    func test_type_when_invalidEncoding() {
        // Given
        let url = URL.test()
        let subject = GoogleCloudStorageClientError.invalidEncoding(url: url,
                                                                    expectedEncoding: "utf8")

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .bug)
    }

    func test_description_when_invalidEncoding() {
        // Given
        let url = URL.test()
        let subject = GoogleCloudStorageClientError.invalidEncoding(url: url,
                                                                    expectedEncoding: "utf8")

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
        XCTAssertThrowsSpecific(try subject.latestVersion().toBlocking().first(),
                                GoogleCloudStorageClientError.invalidVersionFormat("invalid"))
    }

    func test_latestVersion_returns_the_version() throws {
        // Given
        let request = GoogleCloudStorageClient.releasesRequest(path: "latest/version")
        let version = SPMUtility.Version(string: "3.2.1")!
        scheduler.stub(request: request, data: version.description.data(using: .utf8)!)

        // When
        let got = try subject.latestVersion().toBlocking().first()

        // Then
        XCTAssertNotNil(got)
        XCTAssertEqual(got, version)
    }
}
