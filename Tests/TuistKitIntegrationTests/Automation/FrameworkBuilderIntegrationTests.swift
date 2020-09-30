import Foundation
import TSCBasic
import TuistAutomation
import TuistSupport
import XCTest

@testable import TuistCache
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class FrameworkBuilderIntegrationTests: TuistTestCase {
    var subject: FrameworkBuilder!
    var frameworkMetadataProvider: FrameworkMetadataProvider!

    override func setUp() {
        super.setUp()
        frameworkMetadataProvider = FrameworkMetadataProvider()
        subject = FrameworkBuilder(xcodeBuildController: XcodeBuildController())
    }

    override func tearDown() {
        subject = nil
        frameworkMetadataProvider = nil
        super.tearDown()
    }

    func test_build_ios() throws {
        // Given
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let target = Target.test(name: "iOS", platform: .iOS, product: .framework, productName: "iOS")

        // When
        let paths = try subject.build(projectPath: projectPath, target: target).toBlocking().single()
        XCTAssertEqual(paths.count, 1)
        let frameworkPath = try XCTUnwrap(paths.first)

        // Then
        XCTAssertEqual(try binaryLinking(path: frameworkPath), .dynamic)
        XCTAssertTrue(try architectures(path: frameworkPath).contains(.x8664))
        XCTAssertEqual(try architectures(path: frameworkPath).count, 1)

        try FileHandler.shared.delete(frameworkPath)
    }

    func test_build_macos() throws {
        // Given
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let target = Target.test(name: "macOS", platform: .macOS, product: .framework, productName: "macOS")

        // When
        let paths = try subject.build(projectPath: projectPath, target: target).toBlocking().single()
        XCTAssertEqual(paths.count, 1)
        let frameworkPath = try XCTUnwrap(paths.first)

        // Then
        XCTAssertEqual(try binaryLinking(path: frameworkPath), .dynamic)
        XCTAssertTrue(try architectures(path: frameworkPath).contains(.x8664))
        XCTAssertEqual(try architectures(path: frameworkPath).count, 1)

        try FileHandler.shared.delete(frameworkPath)
    }

    func test_build_tvOS() throws {
        // Given
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let target = Target.test(name: "tvOS", platform: .tvOS, product: .framework, productName: "tvOS")

        // When
        let paths = try subject.build(projectPath: projectPath, target: target).toBlocking().single()
        XCTAssertEqual(paths.count, 1)
        let frameworkPath = try XCTUnwrap(paths.first)

        // Then
        XCTAssertEqual(try binaryLinking(path: frameworkPath), .dynamic)
        XCTAssertTrue(try architectures(path: frameworkPath).contains(.x8664))
        XCTAssertEqual(try architectures(path: frameworkPath).count, 1)

        try FileHandler.shared.delete(frameworkPath)
    }

    func test_build_watchOS() throws {
        // Given
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let target = Target.test(name: "watchOS", platform: .watchOS, product: .framework, productName: "watchOS")

        // When
        let paths = try subject.build(projectPath: projectPath, target: target).toBlocking().single()
        XCTAssertEqual(paths.count, 1)
        let frameworkPath = try XCTUnwrap(paths.first)

        // Then
        XCTAssertEqual(try binaryLinking(path: frameworkPath), .dynamic)
        XCTAssertTrue(try architectures(path: frameworkPath).contains(.x8664))
        XCTAssertEqual(try architectures(path: frameworkPath).count, 1)

        try FileHandler.shared.delete(frameworkPath)
    }

    fileprivate func binaryLinking(path: AbsolutePath) throws -> BinaryLinking {
        let binaryPath = FrameworkNode.binaryPath(frameworkPath: path)
        return try frameworkMetadataProvider.linking(binaryPath: binaryPath)
    }

    fileprivate func architectures(path: AbsolutePath) throws -> [BinaryArchitecture] {
        let binaryPath = FrameworkNode.binaryPath(frameworkPath: path)
        return try frameworkMetadataProvider.architectures(binaryPath: binaryPath)
    }
}
