import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class XCFrameworkInfoPlistTests: XCTestCase {
    func test_codable() {
        // Given
        let subject: XCFrameworkInfoPlist = .test()

        // Then
        XCTAssertCodable(subject)
    }

    // MARK: - SupportedPlatformVariant decode (tuist/tuist#9723)

    func test_decode_from_plist_with_SupportedPlatformVariant() throws {
        // Given
        let plistData = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AvailableLibraries</key>
            <array>
                <dict>
                    <key>LibraryIdentifier</key>
                    <string>ios-arm64</string>
                    <key>LibraryPath</key>
                    <string>MyFramework.framework</string>
                    <key>SupportedArchitectures</key>
                    <array>
                        <string>arm64</string>
                    </array>
                    <key>SupportedPlatform</key>
                    <string>ios</string>
                </dict>
                <dict>
                    <key>LibraryIdentifier</key>
                    <string>ios-arm64-simulator</string>
                    <key>LibraryPath</key>
                    <string>MyFramework.framework</string>
                    <key>SupportedArchitectures</key>
                    <array>
                        <string>arm64</string>
                    </array>
                    <key>SupportedPlatform</key>
                    <string>ios</string>
                    <key>SupportedPlatformVariant</key>
                    <string>simulator</string>
                </dict>
            </array>
        </dict>
        </plist>
        """.data(using: .utf8)!

        // When
        let decoded = try PropertyListDecoder().decode(
            XCFrameworkInfoPlist.self,
            from: plistData
        )

        // Then
        XCTAssertEqual(decoded.libraries.count, 2)

        let deviceLib = try XCTUnwrap(
            decoded.libraries.first { $0.identifier == "ios-arm64" }
        )
        let simulatorLib = try XCTUnwrap(
            decoded.libraries.first { $0.identifier == "ios-arm64-simulator" }
        )

        XCTAssertEqual(deviceLib.platform, .iOS)
        XCTAssertNil(deviceLib.platformVariant)

        XCTAssertEqual(simulatorLib.platform, .iOS)
        XCTAssertEqual(simulatorLib.platformVariant, .simulator)
    }
}
