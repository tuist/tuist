import Foundation
import TSCBasic
import TuistAutomation
import TuistSupport
import XCTest
import TuistGraph
import TuistGraphTesting
@testable import TuistCache
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CacheFrameworkBuilderIntegrationTests: TuistTestCase {
    var subject: CacheFrameworkBuilder!
    var frameworkMetadataProvider: FrameworkMetadataProvider!

    override func setUp() {
        super.setUp()
        frameworkMetadataProvider = FrameworkMetadataProvider()
        subject = CacheFrameworkBuilder(xcodeBuildController: XcodeBuildController())
    }

    override func tearDown() {
        subject = nil
        frameworkMetadataProvider = nil
        super.tearDown()
    }

    func test_build_ios() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let target = Target.test(name: "iOS", platform: .iOS, product: .framework, productName: "iOS")

        // When
        try subject.build(projectPath: projectPath, target: target, into: temporaryPath)

        // Then
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.framework").count, 1)
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.dSYM").count, 1)
        let frameworkPath = try XCTUnwrap(FileHandler.shared.glob(temporaryPath, glob: "*.framework").first)
        XCTAssertEqual(try binaryLinking(path: frameworkPath), .dynamic)
        XCTAssertTrue((try architectures(path: frameworkPath)).onlySimulator)
        XCTAssertEqual(try architectures(path: frameworkPath).count, 1)
    }

    func test_build_macos() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let target = Target.test(name: "macOS", platform: .macOS, product: .framework, productName: "macOS")

        // When
        try subject.build(projectPath: projectPath, target: target, into: temporaryPath)

        // Then
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.framework").count, 1)
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.dSYM").count, 1)
        let frameworkPath = try XCTUnwrap(FileHandler.shared.glob(temporaryPath, glob: "*.framework").first)
        XCTAssertEqual(try binaryLinking(path: frameworkPath), .dynamic)
        XCTAssertTrue(try architectures(path: frameworkPath).contains(.x8664))
        XCTAssertEqual(try architectures(path: frameworkPath).count, 1)
    }

    func test_build_tvOS() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let target = Target.test(name: "tvOS", platform: .tvOS, product: .framework, productName: "tvOS")

        // When
        try subject.build(projectPath: projectPath, target: target, into: temporaryPath)

        // Then
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.framework").count, 1)
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.dSYM").count, 1)
        let frameworkPath = try XCTUnwrap(FileHandler.shared.glob(temporaryPath, glob: "*.framework").first)
        XCTAssertEqual(try binaryLinking(path: frameworkPath), .dynamic)
        XCTAssertTrue((try architectures(path: frameworkPath)).onlySimulator)
        XCTAssertEqual(try architectures(path: frameworkPath).count, 1)
    }

    func test_build_watchOS() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let target = Target.test(name: "watchOS", platform: .watchOS, product: .framework, productName: "watchOS")

        // When
        try subject.build(projectPath: projectPath, target: target, into: temporaryPath)

        // Then
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.framework").count, 1)
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.dSYM").count, 1)
        let frameworkPath = try XCTUnwrap(FileHandler.shared.glob(temporaryPath, glob: "*.framework").first)
        XCTAssertEqual(try binaryLinking(path: frameworkPath), .dynamic)
        XCTAssertTrue((try architectures(path: frameworkPath)).onlySimulator)
        XCTAssertEqual(try architectures(path: frameworkPath).count, 1)
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
