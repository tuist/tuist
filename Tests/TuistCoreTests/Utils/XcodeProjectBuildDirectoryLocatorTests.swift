import Foundation
import TSCBasic
import TuistSupportTesting
import XCTest

@testable import TuistCore

final class XcodeProjectBuildDirectoryLocatorTests: TuistTestCase {
    private var derivedDataLocator: MockDerivedDataLocator!
    private var subject: XcodeProjectBuildDirectoryLocator!

    override func setUp() {
        derivedDataLocator = MockDerivedDataLocator()
        subject = XcodeProjectBuildDirectoryLocator(derivedDataLocator: derivedDataLocator)
        super.setUp()
    }

    override func tearDown() {
        derivedDataLocator = nil
        subject = nil
        super.tearDown()
    }

    func test_locate_WHEN_platform_IS_macOS() throws {
        // GIVEN
        let projectName = "TestProject"
        let projectPath = AbsolutePath("/Project/\(projectName)")
        derivedDataLocator.locateStub = { _ in AbsolutePath("/Xcode/DerivedData/\(projectName)") }
        let configuration = "Release"

        // WHEN
        let path = try subject.locate(platform: .macOS, projectPath: projectPath, configuration: configuration)

        // THEN
        let expectedPath = AbsolutePath("/Xcode/DerivedData/\(projectName)/Build/Products/\(configuration)")
        XCTAssertEqual(path, expectedPath)
    }

    func test_locate_WHEN_platform_IS_iOS() throws {
        // GIVEN
        let projectName = "TestProject"
        let projectPath = AbsolutePath("/Project/\(projectName)")
        derivedDataLocator.locateStub = { _ in AbsolutePath("/Xcode/DerivedData/\(projectName)") }
        let configuration = "Release"
        let sdk = "iphonesimulator"

        // WHEN
        let path = try subject.locate(platform: .iOS, projectPath: projectPath, configuration: configuration)

        // THEN
        let expectedPath = AbsolutePath("/Xcode/DerivedData/\(projectName)/Build/Products/\(configuration)-\(sdk)")
        XCTAssertEqual(path, expectedPath)
    }
}
