import Foundation
import MockableTest
import TuistCore
import TuistLoader
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class ProjectViewServiceTests: TuistUnitTestCase {
    var opener: MockOpening!
    var configLoader: MockConfigLoading!
    var subject: ProjectViewService!

    override func setUp() {
        super.setUp()
        opener = MockOpening()
        configLoader = MockConfigLoading()
        subject = ProjectViewService(opener: opener, configLoader: configLoader)
    }

    override func tearDown() {
        opener = nil
        configLoader = nil
        subject = nil
        super.tearDown()
    }

    func test_run_when_theFullHandleIsProvided() async throws {
        // Given
        var expectedURLComponents = URLComponents(url: Constants.URLs.production, resolvingAgainstBaseURL: false)!
        expectedURLComponents.path = "/tuist/tuist"
        given(opener).open(url: .value(expectedURLComponents.url!)).willReturn()

        // When
        try await subject.run(fullHandle: "tuist/tuist", pathString: nil)

        // Then
        verify(opener).open(url: .value(expectedURLComponents.url!)).called(1)
    }

    func test_run_when_theFullHandleIsNotProvided_and_aConfigWithFullHandleCanBeLoaded() async throws {
        // Given
        let path = try temporaryPath()
        var expectedURLComponents = URLComponents(url: Constants.URLs.production, resolvingAgainstBaseURL: false)!
        expectedURLComponents.path = "/tuist/tuist"
        let config = Config.test(fullHandle: "tuist/tuist")
        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(opener).open(url: .value(expectedURLComponents.url!)).willReturn()

        // When
        try await subject.run(fullHandle: nil, pathString: path.pathString)

        // Then
        verify(opener).open(url: .value(expectedURLComponents.url!)).called(1)
    }

    func test_run_when_theFullHandleIsNotProvided_and_aConfigWithoutFullHandleCanBeLoaded() async throws {
        // Given
        let path = try temporaryPath()
        var expectedURLComponents = URLComponents(url: Constants.URLs.production, resolvingAgainstBaseURL: false)!
        expectedURLComponents.path = "/tuist/tuist"
        given(opener).open(url: .value(expectedURLComponents.url!)).willReturn()
        let config = Config.test(fullHandle: nil)
        given(configLoader).loadConfig(path: .value(path)).willReturn(config)

        // When/Then
        await XCTAssertThrowsSpecific({
            try await subject.run(fullHandle: nil, pathString: path.pathString)
        }, ProjectViewServiceError.missingFullHandle)
    }
}
