import Foundation
import MockableTest
import Path
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class SettingsContentHasherTests: TuistUnitTestCase {
    private var subject: SettingsContentHasher!
    private var contentHasher: MockContentHashing!
    private let filePath1 = try! AbsolutePath(validating: "/file1")

    override func setUp() {
        super.setUp()
        contentHasher = .init()
        subject = SettingsContentHasher(contentHasher: contentHasher)

        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: ";") }
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
    }

    override func tearDown() {
        subject = nil
        contentHasher = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hash_whenRecommended_withXCConfig_callsContentHasherWithExpectedStrings() throws {
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("xconfigHash")

        // Given
        let settings = Settings(
            base: ["CURRENT_PROJECT_VERSION": SettingValue.string("1")],
            configurations: [
                BuildConfiguration
                    .debug("dev"): Configuration(settings: ["SWIFT_VERSION": SettingValue.string("5")], xcconfig: filePath1),
            ],
            defaultSettings: .recommended
        )

        // When
        let hash = try subject.hash(settings: settings)

        // Then
        XCTAssertEqual(
            hash,
            "CURRENT_PROJECT_VERSION:string(\"1\")-hash;devdebugSWIFT_VERSION:string(\"5\")-hashxconfigHash;recommended"
        )
    }

    func test_hash_whenEssential_withoutXCConfig_callsContentHasherWithExpectedStrings() throws {
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("xconfigHash")

        // Given
        let settings = Settings(
            base: ["CURRENT_PROJECT_VERSION": SettingValue.string("2")],
            configurations: [
                BuildConfiguration
                    .release("prod"): Configuration(settings: ["SWIFT_VERSION": SettingValue.string("5")], xcconfig: nil),
            ],
            defaultSettings: .essential
        )

        // When
        let hash = try subject.hash(settings: settings)

        // Then
        XCTAssertEqual(hash, "CURRENT_PROJECT_VERSION:string(\"2\")-hash;prodreleaseSWIFT_VERSION:string(\"5\")-hash;essential")
    }
}
