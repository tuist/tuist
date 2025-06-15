import Foundation
import Path
import TuistTesting
import XCTest

@testable import TuistCore

final class XcodeProjectBuildDirectoryLocatorTests: TuistTestCase {
    private var derivedDataLocator: MockDerivedDataLocator!
    private var subject: XcodeProjectBuildDirectoryLocator!

    override func setUp() {
        super.setUp()
        derivedDataLocator = MockDerivedDataLocator()
        subject = XcodeProjectBuildDirectoryLocator(derivedDataLocator: derivedDataLocator)
    }

    override func tearDown() {
        derivedDataLocator = nil
        subject = nil
        super.tearDown()
    }

    func test_locate_WHEN_destination_platform_IS_device_macOS() async throws {
        // GIVEN
        let projectName = "TestProject"
        let projectPath = try AbsolutePath(validating: "/Project/\(projectName)")
        derivedDataLocator.locateStub = { _ in try AbsolutePath(validating: "/Xcode/DerivedData/\(projectName)") }
        let configuration = "Release"

        // WHEN
        let path = try await subject.locate(
            destinationType: .device(.macOS),
            projectPath: projectPath,
            derivedDataPath: nil,
            configuration: configuration
        )

        // THEN
        let expectedPath = try AbsolutePath(validating: "/Xcode/DerivedData/\(projectName)/Build/Products/\(configuration)")
        XCTAssertEqual(path, expectedPath)
    }

    func test_locate_WHEN_destination_platform_IS_simulator_iOS() async throws {
        // GIVEN
        let projectName = "TestProject"
        let projectPath = try AbsolutePath(validating: "/Project/\(projectName)")
        derivedDataLocator.locateStub = { _ in try AbsolutePath(validating: "/Xcode/DerivedData/\(projectName)") }
        let configuration = "Release"
        let sdk = "iphonesimulator"

        // WHEN
        let path = try await subject.locate(
            destinationType: .simulator(.iOS),
            projectPath: projectPath,
            derivedDataPath: nil,
            configuration: configuration
        )

        // THEN
        let expectedPath =
            try AbsolutePath(validating: "/Xcode/DerivedData/\(projectName)/Build/Products/\(configuration)-\(sdk)")
        XCTAssertEqual(path, expectedPath)
    }

    func test_locate_WHEN_destination_platform_IS_device_iOS() async throws {
        // GIVEN
        let projectName = "TestProject"
        let projectPath = try AbsolutePath(validating: "/Project/\(projectName)")
        derivedDataLocator.locateStub = { _ in try AbsolutePath(validating: "/Xcode/DerivedData/\(projectName)") }
        let configuration = "Release"
        let sdk = "iphoneos"

        // WHEN
        let path = try await subject.locate(
            destinationType: .device(.iOS),
            projectPath: projectPath,
            derivedDataPath: nil,
            configuration: configuration
        )

        // THEN
        let expectedPath =
            try AbsolutePath(validating: "/Xcode/DerivedData/\(projectName)/Build/Products/\(configuration)-\(sdk)")
        XCTAssertEqual(path, expectedPath)
    }
}
