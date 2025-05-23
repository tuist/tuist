import Foundation
import Mockable
import struct TSCUtility.Version
import TuistSupport
import TuistSupportTesting
import Testing
import FileSystem
import FileSystemTesting

@testable import TuistSupport

@Suite(.withMockedXcodeController, .inTemporaryDirectory)
struct XCResultControllerTests {
    private var subject: XCResultToolController!
    private let system = MockSystem()
    
    init() throws {
        let mockXcodeController = try #require(XcodeController.mocked)
        given(mockXcodeController)
            .selectedVersion()
            .willReturn(Version(16, 0, 0))

        subject = XCResultToolController(system: system)
    }

    @Test func test_resultBundleObject() async throws {
        // Given
        let resultBundlePath = try #require(FileSystem.temporaryTestDirectory)

        system.succeedCommand(
            [
                "/usr/bin/xcrun", "xcresulttool", "get",
                "--path", resultBundlePath.pathString,
                "--format", "json",
                "--legacy",
            ],
            output: "{some: 'json'}"
        )

        // When
        let got = try await subject.resultBundleObject(resultBundlePath)

        // Then
        #expect(got == "{some: 'json'}")
    }

    @Test func test_resultBundleObject_when_xcode_15() async throws {
        // Given
        let mockXcodeController = try #require(XcodeController.mocked)

        mockXcodeController.reset()
        given(mockXcodeController)
            .selectedVersion()
            .willReturn(Version(15, 3, 0))
        let resultBundlePath = try #require(FileSystem.temporaryTestDirectory)

        system.succeedCommand(
            [
                "/usr/bin/xcrun", "xcresulttool", "get",
                "--path", resultBundlePath.pathString,
                "--format", "json",
            ],
            output: "{some: 'json'}"
        )

        // When
        let got = try await subject.resultBundleObject(resultBundlePath)

        // Then
        #expect(got == "{some: 'json'}")
    }

    @Test func test_resultBundleObject_with_id() async throws {
        // Given
        let resultBundlePath = try #require(FileSystem.temporaryTestDirectory)

        system.succeedCommand(
            [
                "/usr/bin/xcrun", "xcresulttool", "get",
                "--path", resultBundlePath.pathString,
                "--id", "some-id",
                "--format", "json",
                "--legacy",
            ],
            output: "{some: 'json'}"
        )

        // When
        let got = try await subject.resultBundleObject(
            resultBundlePath,
            id: "some-id"
        )

        // Then
        #expect(got == "{some: 'json'}")
    }

    @Test func test_resultBundleObject_with_id_when_xcode_15() async throws {
        // Given
        let mockXcodeController = try #require(XcodeController.mocked)

        mockXcodeController.reset()
        given(mockXcodeController)
            .selectedVersion()
            .willReturn(Version(15, 3, 0))
        let resultBundlePath = try #require(FileSystem.temporaryTestDirectory)

        system.succeedCommand(
            [
                "/usr/bin/xcrun", "xcresulttool", "get",
                "--path", resultBundlePath.pathString,
                "--id", "some-id",
                "--format", "json",
            ],
            output: "{some: 'json'}"
        )

        // When
        let got = try await subject.resultBundleObject(
            resultBundlePath,
            id: "some-id"
        )

        // Then
        #expect(got == "{some: 'json'}")
    }
}
