import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistHasher

struct SettingsContentHasherTests {
    private let subject: SettingsContentHasher
    private let contentHasher: MockContentHashing
    private let xcconfigHasher: MockXCConfigContentHashing
    private let filePath1 = try! AbsolutePath(validating: "/file1")

    init() {
        contentHasher = .init()
        xcconfigHasher = .init()
        subject = SettingsContentHasher(contentHasher: contentHasher, xcconfigHasher: xcconfigHasher)
        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: ";") }
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
    }

    // MARK: - Tests

    @Test
    func hash_whenRecommended_withXCConfig_callsContentHasherWithExpectedStrings() async throws {
        given(xcconfigHasher)
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
        let hash = try await subject.hash(settings: settings)

        // Then
        #expect(hash ==
            "CURRENT_PROJECT_VERSION:string(\"1\")-hash;devdebugSWIFT_VERSION:string(\"5\")-hashxconfigHash;recommended")
    }

    @Test
    func hash_whenEssential_withoutXCConfig_callsContentHasherWithExpectedStrings() async throws {
        given(xcconfigHasher)
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
        let hash = try await subject.hash(settings: settings)

        // Then
        #expect(hash == "CURRENT_PROJECT_VERSION:string(\"2\")-hash;prodreleaseSWIFT_VERSION:string(\"5\")-hash;essential")
    }

    @Test
    func hash_filtersWarningFlags() async throws {
        // Given
        let settings = Settings(
            base: [
                "SWIFT_VERSION": SettingValue.string("5"),
                "OTHER_SWIFT_FLAGS": SettingValue
                    .array([
                        "-Xfrontend",
                        "-warn-long-function-bodies=450",
                        "-Xfrontend",
                        "-enable-actor-data-race-checks",
                        "-O",
                        "-Xfrontend",
                        "-warn-concurrency",
                    ]),
            ],
            configurations: [
                BuildConfiguration.debug("Debug"): Configuration(
                    settings: [
                        "GCC_OPTIMIZATION_LEVEL": SettingValue.string("0"),
                        "OTHER_SWIFT_FLAGS": SettingValue
                            .array(["-Xfrontend", "-warn-long-expression-type-checking=300"]),
                    ],
                    xcconfig: nil
                ),
            ],
            defaultSettings: .none
        )

        // When
        let hash = try await subject.hash(settings: settings)

        // Then: Warning flags should be filtered out, but non-warning flags should be kept
        #expect(hash ==
            "OTHER_SWIFT_FLAGS:array([\"-Xfrontend\", \"-enable-actor-data-race-checks\", \"-O\"])-SWIFT_VERSION:string(\"5\")-hash;DebugdebugGCC_OPTIMIZATION_LEVEL:string(\"0\")-hash;none")
    }
}
