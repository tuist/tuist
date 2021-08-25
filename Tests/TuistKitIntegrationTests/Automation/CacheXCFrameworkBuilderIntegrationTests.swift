import Foundation
import TSCBasic
import TuistAutomation
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest
@testable import TuistCache
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CacheXCFrameworkBuilderIntegrationTests: TuistTestCase {
    var subject: CacheXCFrameworkBuilder!
    var plistDecoder: PropertyListDecoder!

    override func setUp() {
        super.setUp()
        plistDecoder = PropertyListDecoder()
        subject = CacheXCFrameworkBuilder(xcodeBuildController: XcodeBuildController())
    }

    override func tearDown() {
        subject = nil
        plistDecoder = nil
        super.tearDown()
    }

    func test_build_when_iOS_framework() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let scheme = Scheme.test(name: "iOS")

        // When
        try subject.build(scheme: scheme, projectTarget: XcodeBuildTarget(with: projectPath), configuration: "Debug", into: temporaryPath)

        // Then
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.xcframework").count, 1)
        let xcframeworkPath = try XCTUnwrap(FileHandler.shared.glob(temporaryPath, glob: "*.xcframework").first)
        let infoPlist = try self.infoPlist(xcframeworkPath: xcframeworkPath)
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("arm64") }))
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("x86_64") }))
        XCTAssertTrue(infoPlist.availableLibraries.allSatisfy { $0.supportedPlatform == "ios" })
        try FileHandler.shared.delete(xcframeworkPath)
    }

    func test_build_when_macOS_framework() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let scheme = Scheme.test(name: "macOS")

        // When
        try subject.build(scheme: scheme, projectTarget: XcodeBuildTarget(with: projectPath), configuration: "Debug", into: temporaryPath)

        // Then
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.xcframework").count, 1)
        let xcframeworkPath = try XCTUnwrap(FileHandler.shared.glob(temporaryPath, glob: "*.xcframework").first)
        let infoPlist = try self.infoPlist(xcframeworkPath: xcframeworkPath)
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { library in
            library.supportedArchitectures.contains("x86_64") || library.supportedArchitectures.contains("arm64")
        }))
        XCTAssertTrue(infoPlist.availableLibraries.allSatisfy { $0.supportedPlatform == "macos" })
        try FileHandler.shared.delete(xcframeworkPath)
    }

    func test_build_when_tvOS_framework() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let scheme = Scheme.test(name: "tvOS")

        // When
        try subject.build(scheme: scheme, projectTarget: XcodeBuildTarget(with: projectPath), configuration: "Debug", into: temporaryPath)

        // Then
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.xcframework").count, 1)
        let xcframeworkPath = try XCTUnwrap(FileHandler.shared.glob(temporaryPath, glob: "*.xcframework").first)
        let infoPlist = try self.infoPlist(xcframeworkPath: xcframeworkPath)
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("x86_64") }))
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("arm64") }))
        XCTAssertTrue(infoPlist.availableLibraries.allSatisfy { $0.supportedPlatform == "tvos" })
        try FileHandler.shared.delete(xcframeworkPath)
    }

    func test_build_when_watchOS_framework() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let scheme = Scheme.test(name: "watchOS")

        // When
        try subject.build(scheme: scheme, projectTarget: XcodeBuildTarget(with: projectPath), configuration: "Debug", into: temporaryPath)

        // Then
        XCTAssertEqual(FileHandler.shared.glob(temporaryPath, glob: "*.xcframework").count, 1)
        let xcframeworkPath = try XCTUnwrap(FileHandler.shared.glob(temporaryPath, glob: "*.xcframework").first)
        let infoPlist = try self.infoPlist(xcframeworkPath: xcframeworkPath)
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("i386") }))
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("armv7k") }))
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("arm64_32") }))
        XCTAssertTrue(infoPlist.availableLibraries.allSatisfy { $0.supportedPlatform == "watchos" })
        try FileHandler.shared.delete(xcframeworkPath)
    }

    fileprivate func infoPlist(xcframeworkPath: AbsolutePath) throws -> XCFrameworkInfoPlist {
        let infoPlistPath = xcframeworkPath.appending(component: "Info.plist")
        let data = try Data(contentsOf: infoPlistPath.url)
        return try plistDecoder.decode(XCFrameworkInfoPlist.self, from: data)
    }
}

private struct XCFrameworkInfoPlist: Decodable {
    let availableLibraries: [Library]

    enum CodingKeys: String, CodingKey {
        case availableLibraries = "AvailableLibraries"
    }

    fileprivate struct Library: Decodable {
        let identifier: String
        let path: String
        let supportedArchitectures: [String]
        let supportedPlatform: String

        enum CodingKeys: String, CodingKey {
            case identifier = "LibraryIdentifier"
            case path = "LibraryPath"
            case supportedArchitectures = "SupportedArchitectures"
            case supportedPlatform = "SupportedPlatform"
        }
    }
}
