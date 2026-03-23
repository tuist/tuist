import Foundation
import Path
import TuistTesting
import Testing

@testable import TuistCore

struct XcodeProjectBuildDirectoryLocatorTests {
    let derivedDataLocator: MockDerivedDataLocator
    let subject: XcodeProjectBuildDirectoryLocator

    init() {
        derivedDataLocator = MockDerivedDataLocator()
        subject = XcodeProjectBuildDirectoryLocator(derivedDataLocator: derivedDataLocator)
    }

    @Test func test_locate_WHEN_destination_platform_IS_device_macOS() async throws {
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
        #expect(path == expectedPath)
    }

    @Test func test_locate_WHEN_destination_platform_IS_simulator_iOS() async throws {
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
        #expect(path == expectedPath)
    }

    @Test func test_locate_WHEN_destination_platform_IS_device_iOS() async throws {
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
        #expect(path == expectedPath)
    }
}
