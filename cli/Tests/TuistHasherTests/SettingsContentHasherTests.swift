import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class SettingsContentHasherTests: TuistUnitTestCase {
    private var subject: SettingsContentHasher!
    private var contentHasher: MockContentHashing!
    private var xcconfigHasher: MockXCConfigContentHashing!
    private let filePath1 = try! AbsolutePath(validating: "/file1")

    override func setUp() {
        super.setUp()
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

    override func tearDown() {
        subject = nil
        contentHasher = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hash_whenRecommended_withXCConfig_callsContentHasherWithExpectedStrings() async throws {
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
        XCTAssertEqual(
            hash,
            "CURRENT_PROJECT_VERSION:string(\"1\")-hash;devdebugSWIFT_VERSION:string(\"5\")-hashxconfigHash;recommended"
        )
    }

    func test_hash_whenEssential_withoutXCConfig_callsContentHasherWithExpectedStrings() async throws {
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
        XCTAssertEqual(hash, "CURRENT_PROJECT_VERSION:string(\"2\")-hash;prodreleaseSWIFT_VERSION:string(\"5\")-hash;essential")
    }

    func test_hash_filtersWarningFlags() async throws {
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
        XCTAssertEqual(
            hash,
            "OTHER_SWIFT_FLAGS:array([\"-Xfrontend\", \"-enable-actor-data-race-checks\", \"-O\"])-SWIFT_VERSION:string(\"5\")-hash;DebugdebugGCC_OPTIMIZATION_LEVEL:string(\"0\")-hash;none"
        )
    }
}

struct SettingsContentHasherBaseDebugTests {
    @Test func hash_includesBaseDebugSettings() async throws {
        // Given
        let contentHasher = MockContentHashing()
        let xcconfigHasher = MockXCConfigContentHashing()
        let subject = SettingsContentHasher(contentHasher: contentHasher, xcconfigHasher: xcconfigHasher)
        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: ";") }
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
        let settings = Settings(
            base: ["CURRENT_PROJECT_VERSION": SettingValue.string("1")],
            baseDebug: ["ENABLE_TESTING_SEARCH_PATHS": SettingValue.string("YES")],
            configurations: [
                BuildConfiguration.debug("Debug"): nil,
            ],
            defaultSettings: .recommended
        )

        // When
        let hash = try await subject.hash(settings: settings)

        // Then
        #expect(
            hash
                == "CURRENT_PROJECT_VERSION:string(\"1\")-hash;ENABLE_TESTING_SEARCH_PATHS:string(\"YES\")-hash;Debugdebug;recommended"
        )
    }
}

struct SettingsContentHasherCompilationCacheTests {
    private func makeSubject() -> SettingsContentHasher {
        let contentHasher = MockContentHashing()
        let xcconfigHasher = MockXCConfigContentHashing()
        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: ";") }
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
        return SettingsContentHasher(contentHasher: contentHasher, xcconfigHasher: xcconfigHasher)
    }

    private func settings(base: SettingsDictionary) -> Settings {
        Settings(base: base, configurations: [BuildConfiguration.debug("Debug"): nil], defaultSettings: .none)
    }

    /// The compilation-cache settings select where a compilation caches, not what it
    /// produces. `COMPILATION_CACHE_PLUGIN_PATH` in particular holds the dylib's
    /// install path, which differs between a Homebrew install and a mise one, so
    /// hashing it gives developer machines and CI disjoint keys for identical code.
    @Test func hash_ignoresCompilationCacheSettings() async throws {
        // Given
        let subject = makeSubject()
        let withoutCacheSettings = settings(base: ["SWIFT_VERSION": .string("5")])
        let withCacheSettings = settings(base: [
            "SWIFT_VERSION": .string("5"),
            "COMPILATION_CACHE_ENABLE_CACHING": .string("YES"),
            "COMPILATION_CACHE_ENABLE_PLUGIN": .string("YES"),
            "COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS": .string("YES"),
            "COMPILATION_CACHE_PLUGIN_PATH": .string("/opt/homebrew/lib/libtuist_cas_plugin.dylib"),
            "COMPILATION_CACHE_REMOTE_SERVICE_PATH": .string("$HOME/.local/state/tuist/cas-proxy.sock"),
        ])

        // When / Then
        #expect(try await subject.hash(settings: withCacheSettings) == subject.hash(settings: withoutCacheSettings))
    }

    /// Two machines that resolve the plugin to different install paths must agree.
    @Test func hash_ignoresCompilationCachePluginPathDifferences() async throws {
        // Given
        let subject = makeSubject()
        let homebrew = settings(base: [
            "COMPILATION_CACHE_PLUGIN_PATH": .string("/opt/homebrew/lib/libtuist_cas_plugin.dylib"),
        ])
        let mise = settings(base: [
            "COMPILATION_CACHE_PLUGIN_PATH": .string("/Users/ci/.local/share/mise/installs/tuist/lib/libtuist_cas_plugin.dylib"),
        ])

        // When / Then
        #expect(try await subject.hash(settings: homebrew) == subject.hash(settings: mise))
    }

    /// `xcodeCache(upload:)` reaches the build as a `-cas-plugin-option` pair rather
    /// than a `COMPILATION_CACHE_*` key, so filtering by key alone would still split
    /// CI from local for the documented `upload: Environment.isCI` policy.
    @Test func hash_ignoresCASPluginOptionsInOtherSwiftFlags() async throws {
        // Given
        let subject = makeSubject()
        let uploading = settings(base: [
            "OTHER_SWIFT_FLAGS": .array([
                "$(inherited)",
                "-cas-plugin-option", "tuist-instance=test-org/test-project",
            ]),
        ])
        let readOnly = settings(base: [
            "OTHER_SWIFT_FLAGS": .array([
                "$(inherited)",
                "-cas-plugin-option", "tuist-instance=test-org/test-project",
                "-cas-plugin-option", "tuist-upload=false",
            ]),
        ])

        // When / Then
        #expect(try await subject.hash(settings: uploading) == subject.hash(settings: readOnly))
    }

    /// The filter must not swallow flags that do change the built product.
    @Test func hash_keepsNonCASPluginOtherSwiftFlags() async throws {
        // Given
        let subject = makeSubject()
        let plain = settings(base: [
            "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-cas-plugin-option", "tuist-upload=false"]),
        ])
        let withRealFlag = settings(base: [
            "OTHER_SWIFT_FLAGS": .array([
                "$(inherited)", "-cas-plugin-option", "tuist-upload=false", "-DFEATURE_FLAG",
            ]),
        ])

        // When / Then
        #expect(try await subject.hash(settings: plain) != subject.hash(settings: withRealFlag))
    }
}
