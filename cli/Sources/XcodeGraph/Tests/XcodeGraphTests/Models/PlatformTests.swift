import Foundation
import Testing
@testable import XcodeGraph

struct PlatformTests {
    @Test func test_codable_iOS() throws {
        // Given
        let subject = Platform.iOS

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Platform.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_codable_tvOS() throws {
        // Given
        let subject = Platform.tvOS

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Platform.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_caseInsensitiveCommandInput() {
        #expect(Platform.macOS == Platform(commandLineValue: "macos"))
        #expect(Platform.macOS == Platform(commandLineValue: "macOS"))
        #expect(Platform.macOS == Platform(commandLineValue: "MACOS"))
        #expect(Platform.iOS == Platform(commandLineValue: "ios"))
        #expect(Platform.iOS == Platform(commandLineValue: "iOS"))
        #expect(Platform.iOS == Platform(commandLineValue: "IOS"))
        #expect(Platform.tvOS == Platform(commandLineValue: "tvos"))
        #expect(Platform.tvOS == Platform(commandLineValue: "tvOS"))
        #expect(Platform.watchOS == Platform(commandLineValue: "watchos"))
        #expect(Platform.watchOS == Platform(commandLineValue: "watchOS"))
        #expect(Platform.visionOS == Platform(commandLineValue: "visionos"))
        #expect(Platform.visionOS == Platform(commandLineValue: "visionOS"))
    }

    @Test func test_caseInvalidPlatform_throws() {
        do {
            _ = try Platform.from(commandLineValue: "not_a_platform")
            Issue.record("Expected erro to be thrown")
        } catch let error as UnsupportedPlatformError {
            #expect(error == UnsupportedPlatformError(input: "not_a_platform"))
        } catch {
            Issue.record("Unexpected error thrown")
        }
    }

    @Test func test_caseValidPlatform_doesNotThrow() throws {
        #expect(Platform.iOS == try Platform.from(commandLineValue: "iOS"))
        #expect(Platform.macOS == try Platform.from(commandLineValue: "macOS"))
        #expect(Platform.macOS == try Platform.from(commandLineValue: "macos"))
    }

    @Test func test_xcodeSdkRoot_returns_the_right_value() {
        #expect(Platform.macOS.xcodeSdkRoot == "macosx")
        #expect(Platform.iOS.xcodeSdkRoot == "iphoneos")
        #expect(Platform.tvOS.xcodeSdkRoot == "appletvos")
        #expect(Platform.watchOS.xcodeSdkRoot == "watchos")
        #expect(Platform.visionOS.xcodeSdkRoot == "xros")
    }

    @Test func test_xcodeSimulatorSDK() {
        #expect(Platform.tvOS.xcodeSimulatorSDK == "appletvsimulator")
        #expect(Platform.iOS.xcodeSimulatorSDK == "iphonesimulator")
        #expect(Platform.watchOS.xcodeSimulatorSDK == "watchsimulator")
        #expect(Platform.visionOS.xcodeSimulatorSDK == "xrsimulator")
        #expect(Platform.macOS.xcodeSimulatorSDK == nil)
    }

    @Test func test_xcodeDeviceSDK() {
        #expect(Platform.tvOS.xcodeDeviceSDK == "appletvos")
        #expect(Platform.iOS.xcodeDeviceSDK == "iphoneos")
        #expect(Platform.watchOS.xcodeDeviceSDK == "watchos")
        #expect(Platform.macOS.xcodeDeviceSDK == "macosx")
        #expect(Platform.visionOS.xcodeDeviceSDK == "xros")
    }

    @Test func test_hasSimulators() {
        #expect(!Platform.macOS.hasSimulators)
        #expect(Platform.tvOS.hasSimulators)
        #expect(Platform.watchOS.hasSimulators)
        #expect(Platform.tvOS.hasSimulators)
        #expect(Platform.visionOS.hasSimulators)
    }

    @Test func test_xcodeSdkRootPath() {
        // Given
        let platforms: [Platform] = [
            .iOS,
            .macOS,
            .tvOS,
            .watchOS,
            .visionOS,
        ]

        // When
        let paths = platforms.map(\.xcodeSdkRootPath)

        // Then
        #expect(paths == [
            "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk",
            "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
            "Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk",
            "Platforms/WatchOS.platform/Developer/SDKs/WatchOS.sdk",
            "Platforms/XROS.platform/Developer/SDKs/XROS.sdk",
        ])
    }
}
