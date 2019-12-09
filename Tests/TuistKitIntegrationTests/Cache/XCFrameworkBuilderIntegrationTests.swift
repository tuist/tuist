import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class XCFrameworkBuilderIntegrationTests: TuistTestCase {
    var subject: XCFrameworkBuilder!
    var plistDecoder: PropertyListDecoder!

    override func setUp() {
        super.setUp()
        plistDecoder = PropertyListDecoder()
        subject = XCFrameworkBuilder(printOutput: false)
    }

    override func tearDown() {
        subject = nil
        plistDecoder = nil
        super.tearDown()
    }

    func test_build_when_iOS_framework() throws {
        // Given
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let target = Target.test(name: "iOS", platform: .iOS, product: .framework, productName: "iOS")

        // When
        let xcframeworkPath = try subject.build(projectPath: projectPath, target: target)
        let infoPlist = try self.infoPlist(xcframeworkPath: xcframeworkPath)

        // Then
        XCTAssertTrue(FileHandler.shared.exists(xcframeworkPath))
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("arm64") }))
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("x86_64") }))
        XCTAssertTrue(infoPlist.availableLibraries.allSatisfy { $0.supportedPlatform == "ios" })
        XCTAssertPrinterOutputContains("""
        Building .xcframework for iOS
        Building iOS for device
        Building iOS for simulator
        Exporting xcframework for iOS
        """)
        try FileHandler.shared.delete(xcframeworkPath)
    }

    func test_build_when_macOS_framework() throws {
        // Given
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let target = Target.test(name: "macOS", platform: .macOS, product: .framework, productName: "macOS")

        // When
        let xcframeworkPath = try subject.build(projectPath: projectPath, target: target)
        let infoPlist = try self.infoPlist(xcframeworkPath: xcframeworkPath)

        // Then
        XCTAssertTrue(FileHandler.shared.exists(xcframeworkPath))
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("x86_64") }))
        XCTAssertTrue(infoPlist.availableLibraries.allSatisfy { $0.supportedPlatform == "macos" })
        XCTAssertPrinterOutputContains("""
        Building .xcframework for macOS
        Building macOS for device
        Exporting xcframework for macOS
        """)
        try FileHandler.shared.delete(xcframeworkPath)
    }

    func test_build_when_tvOS_framework() throws {
        // Given
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let target = Target.test(name: "tvOS", platform: .tvOS, product: .framework, productName: "tvOS")

        // When
        let xcframeworkPath = try subject.build(projectPath: projectPath, target: target)
        let infoPlist = try self.infoPlist(xcframeworkPath: xcframeworkPath)

        // Then
        XCTAssertTrue(FileHandler.shared.exists(xcframeworkPath))
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("x86_64") }))
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("arm64") }))
        XCTAssertTrue(infoPlist.availableLibraries.allSatisfy { $0.supportedPlatform == "tvos" })
        XCTAssertPrinterOutputContains("""
        Building .xcframework for tvOS
        Building tvOS for device
        Building tvOS for simulator
        Exporting xcframework for tvOS
        """)
        try FileHandler.shared.delete(xcframeworkPath)
    }

    func test_build_when_watchOS_framework() throws {
        // Given
        let frameworksPath = try temporaryFixture("Frameworks")
        let projectPath = frameworksPath.appending(component: "Frameworks.xcodeproj")
        let target = Target.test(name: "watchOS", platform: .watchOS, product: .framework, productName: "watchOS")

        // When
        let xcframeworkPath = try subject.build(projectPath: projectPath, target: target)
        let infoPlist = try self.infoPlist(xcframeworkPath: xcframeworkPath)

        // Then
        XCTAssertTrue(FileHandler.shared.exists(xcframeworkPath))
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("i386") }))
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("armv7k") }))
        XCTAssertNotNil(infoPlist.availableLibraries.first(where: { $0.supportedArchitectures.contains("arm64_32") }))
        XCTAssertTrue(infoPlist.availableLibraries.allSatisfy { $0.supportedPlatform == "watchos" })
        XCTAssertPrinterOutputContains("""
        Building .xcframework for watchOS
        Building watchOS for device
        Building watchOS for simulator
        Exporting xcframework for watchOS
        """)
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
