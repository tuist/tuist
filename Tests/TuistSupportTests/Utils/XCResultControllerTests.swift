import Foundation
import Mockable
import struct TSCUtility.Version
import TuistSupportTesting
import XCTest

@testable import TuistSupport

final class XCResultControllerTests: TuistUnitTestCase {
    private var subject: XCResultToolController!

    override func setUp() {
        super.setUp()

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(16, 0, 0))

        subject = XCResultToolController(
            system: system,
            xcodeController: xcodeController
        )
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func test_resultBundleObject() async throws {
        // Given
        let resultBundlePath = try temporaryPath()

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
        XCTAssertEqual(got, "{some: 'json'}")
    }

    func test_resultBundleObject_when_xcode_15() async throws {
        // Given
        xcodeController.reset()
        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 3, 0))
        let resultBundlePath = try temporaryPath()

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
        XCTAssertEqual(got, "{some: 'json'}")
    }

    func test_resultBundleObject_with_id() async throws {
        // Given
        let resultBundlePath = try temporaryPath()

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
        XCTAssertEqual(got, "{some: 'json'}")
    }

    func test_resultBundleObject_with_id_when_xcode_15() async throws {
        // Given
        xcodeController.reset()
        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 3, 0))
        let resultBundlePath = try temporaryPath()

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
        XCTAssertEqual(got, "{some: 'json'}")
    }
}
