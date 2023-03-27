import Foundation
import TSCBasic
import TuistAutomation
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest
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

    func test_build_ios() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let scheme = Scheme.test(name: "iOS")
        let graph = Graph.test()

        // When
        try await subject.build(
            graph: graph,
            scheme: scheme,
            projectTarget: XcodeBuildTarget(with: projectPath),
            configuration: "Debug",
            osVersion: nil,
            deviceName: nil,
            into: temporaryPath
        )

        // Then
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.framework").count, 1)
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.dSYM").count, 1)
        let frameworkPath = try XCTUnwrap(FileHandler.shared.glob(temporaryPath, glob: "*.framework").first)
        XCTAssertEqual(try binaryLinking(path: frameworkPath), .dynamic)
        XCTAssertTrue((try architectures(path: frameworkPath)).onlySimulator)
        XCTAssertEqual(try architectures(path: frameworkPath).count, 1)
    }

    func test_build_macos() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let scheme = Scheme.test(name: "macOS")
        let graph = Graph.test()

        // When
        try await subject.build(
            graph: graph,
            scheme: scheme,
            projectTarget: XcodeBuildTarget(with: projectPath),
            configuration: "Debug",
            osVersion: nil,
            deviceName: nil,
            into: temporaryPath
        )

        // Then
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.framework").count, 1)
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.dSYM").count, 1)
        let frameworkPath = try XCTUnwrap(FileHandler.shared.glob(temporaryPath, glob: "*.framework").first)
        XCTAssertEqual(try binaryLinking(path: frameworkPath), .dynamic)
        switch DeveloperEnvironment.shared.architecture {
        case .arm64:
            XCTAssertTrue(try architectures(path: frameworkPath).contains(.arm64))
        case .x8664:
            XCTAssertTrue(try architectures(path: frameworkPath).contains(.x8664))
        }
        XCTAssertEqual(try architectures(path: frameworkPath).count, 1)
    }

    // TODO: investigate why this is failing in CI
    // func test_build_tvOS() async throws {
    //     // Given
    //     let temporaryPath = try temporaryPath()
    //     let frameworksPath = try temporaryFixture("Frameworks")
    //     let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
    //     let scheme = Scheme.test(name: "tvOS")

    //     // When
    //     try await subject.build(
    //         scheme: scheme,
    //         projectTarget: XcodeBuildTarget(with: projectPath),
    //         configuration: "Debug",
    //         osVersion: nil,
    //         deviceName: nil,
    //         into: temporaryPath
    //     )

    //     // Then
    //     XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.framework").count, 1)
    //     XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.dSYM").count, 1)
    //     let frameworkPath = try XCTUnwrap(FileHandler.shared.glob(temporaryPath, glob: "*.framework").first)
    //     XCTAssertEqual(try binaryLinking(path: frameworkPath), .dynamic)
    //     XCTAssertTrue((try architectures(path: frameworkPath)).onlySimulator)
    //     XCTAssertEqual(try architectures(path: frameworkPath).count, 1)
    // }

    // TODO: investigate why this is failing in CI
    // func test_build_watchOS() async throws {
    //     // Given
    //     let temporaryPath = try temporaryPath()
    //     let frameworksPath = try temporaryFixture("Frameworks")
    //     let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
    //     let scheme = Scheme.test(name: "watchOS")

    //     // When
    //     try await subject.build(
    //         scheme: scheme,
    //         projectTarget: XcodeBuildTarget(with: projectPath),
    //         configuration: "Debug",
    //         osVersion: nil,
    //         deviceName: nil,
    //         into: temporaryPath
    //     )

    //     // Then
    //     XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.framework").count, 1)
    //     XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.dSYM").count, 1)
    //     let frameworkPath = try XCTUnwrap(FileHandler.shared.glob(temporaryPath, glob: "*.framework").first)
    //     XCTAssertEqual(try binaryLinking(path: frameworkPath), .dynamic)
    //     XCTAssertTrue((try architectures(path: frameworkPath)).onlySimulator)
    //     XCTAssertEqual(try architectures(path: frameworkPath).count, 1)
    // }

    fileprivate func binaryLinking(path: AbsolutePath) throws -> BinaryLinking {
        let binaryPath = try FrameworkMetadataProvider().loadMetadata(at: path).binaryPath
        return try frameworkMetadataProvider.linking(binaryPath: binaryPath)
    }

    fileprivate func architectures(path: AbsolutePath) throws -> [BinaryArchitecture] {
        let binaryPath = try FrameworkMetadataProvider().loadMetadata(at: path).binaryPath
        return try frameworkMetadataProvider.architectures(binaryPath: binaryPath)
    }
}
