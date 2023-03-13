import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class SettingsTests: XCTestCase {
    private var encoder = JSONEncoder()
    private var decoder = JSONDecoder()

    func test_codable_release_debug() throws {
        // Given
        let debug: Configuration = .debug(
            name: .debug,
            settings: ["debug": .string("debug")],
            xcconfig: "/path/debug.xcconfig"
        )
        let release: Configuration = .release(
            name: .release,
            settings: ["release": .string("release")],
            xcconfig: "/path/release"
        )
        let subject: Settings = .settings(
            base: ["base": .string("base")],
            configurations: [
                debug,
                release,
            ]
        )

        // When
        let data = try encoder.encode(subject)

        // Then
        let decoded = try decoder.decode(Settings.self, from: data)
        XCTAssertEqual(decoded, subject)
        XCTAssertEqual(decoded.configurations.map(\.name), [
            "Debug",
            "Release",
        ])
    }

    func test_codable_config_with_exclusions() throws {
        // Given
        let recommendedSubject = Settings(
            base: [:],
            configurations: [],
            defaultSettings: .recommended(excluding: ["someRecommendedKey", "anotherKey"])
        )
        let essentialSubject = Settings(
            base: [:],
            configurations: [],
            defaultSettings: .essential(excluding: ["someEssentialKey", "anotherKey"])
        )

        // Then
        XCTAssertCodable(recommendedSubject)
        XCTAssertCodable(essentialSubject)
    }

    func test_codable_multi_configs() throws {
        // Given
        let configurations: [Configuration] = [
            .debug(name: .debug),
            .debug(name: "CustomDebug", settings: ["CUSTOM_FLAG": .string("Debug")], xcconfig: "debug.xcconfig"),
            .release(name: .release),
            .release(name: "CustomRelease", settings: ["CUSTOM_FLAG": .string("Release")], xcconfig: "release.xcconfig"),
        ]
        let subject: Settings = .settings(
            base: ["base": .string("base")],
            configurations: configurations
        )

        // When
        let data = try encoder.encode(subject)

        // Then
        let decoded = try decoder.decode(Settings.self, from: data)
        XCTAssertEqual(decoded, subject)
        XCTAssertEqual(decoded.configurations.map(\.name), [
            "Debug",
            "CustomDebug",
            "Release",
            "CustomRelease",
        ])
    }

    func test_settingsDictionary_chainingMultipleValues() {
        /// Given / When
        let settings = SettingsDictionary()
            .codeSignIdentityAppleDevelopment()
            .currentProjectVersion("999")
            .marketingVersion("1.0.0")
            .automaticCodeSigning(devTeam: "123ABC")
            .appleGenericVersioningSystem()
            .versionInfo("NLR", prefix: "A_Prefix", suffix: "A_Suffix")
            .swiftVersion("5.2.1")
            .otherSwiftFlags("first", "second", "third")
            .bitcodeEnabled(true)
            .debugInformationFormat(.dwarf)
            .swiftActiveCompilationConditions("FIRST", "SECOND", "THIRD")
            .swiftObjcBridgingHeaderPath("/my/bridging/header/path.h")
            .otherCFlags(["$(inherited)", "-my-c-flag"])
            .otherLinkerFlags(["$(inherited)", "-my-linker-flag"])

        /// Then
        XCTAssertEqual(settings, [
            "CODE_SIGN_IDENTITY": "Apple Development",
            "CURRENT_PROJECT_VERSION": "999",
            "MARKETING_VERSION": "1.0.0",
            "CODE_SIGN_STYLE": "Automatic",
            "DEVELOPMENT_TEAM": "123ABC",
            "VERSIONING_SYSTEM": "apple-generic",
            "VERSION_INFO_STRING": "NLR",
            "VERSION_INFO_PREFIX": "A_Prefix",
            "VERSION_INFO_SUFFIX": "A_Suffix",
            "SWIFT_VERSION": "5.2.1",
            "OTHER_SWIFT_FLAGS": "first second third",
            "ENABLE_BITCODE": "YES",
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "FIRST SECOND THIRD",
            "SWIFT_OBJC_BRIDGING_HEADER": "/my/bridging/header/path.h",
            "OTHER_CFLAGS": ["$(inherited)", "-my-c-flag"],
            "OTHER_LDFLAGS": ["$(inherited)", "-my-linker-flag"],
        ])
    }

    func test_settingsDictionary_codeSignManual() {
        /// Given/When
        let settings = SettingsDictionary()
            .manualCodeSigning(identity: "Apple Distribution", provisioningProfileSpecifier: "ABC")

        /// Then
        XCTAssertEqual(settings, [
            "CODE_SIGN_STYLE": "Manual",
            "CODE_SIGN_IDENTITY": "Apple Distribution",
            "PROVISIONING_PROFILE_SPECIFIER": "ABC",
        ])
    }

    func test_settingsDictionary_swiftActiveCompilationConditions() {
        /// Given/When
        let settings = SettingsDictionary()
            .swiftActiveCompilationConditions("FIRST", "SECOND", "THIRD")

        /// Then
        XCTAssertEqual(settings, [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "FIRST SECOND THIRD",
        ])
    }

    func test_settingsDictionary_SwiftCompilationMode() {
        /// Given/When
        let settings1 = SettingsDictionary()
            .swiftCompilationMode(.singlefile)

        /// Then
        XCTAssertEqual(settings1, [
            "SWIFT_COMPILATION_MODE": "singlefile",
        ])

        /// Given/When
        let settings2 = SettingsDictionary()
            .swiftCompilationMode(.wholemodule)

        /// Then
        XCTAssertEqual(settings2, [
            "SWIFT_COMPILATION_MODE": "wholemodule",
        ])
    }

    func test_settingsDictionary_SwiftOptimizationLevel() {
        /// Given/When
        let settings1 = SettingsDictionary()
            .swiftOptimizationLevel(.o)

        /// Then
        XCTAssertEqual(settings1, [
            "SWIFT_OPTIMIZATION_LEVEL": "-O",
        ])

        /// Given/When
        let settings2 = SettingsDictionary()
            .swiftOptimizationLevel(.oNone)

        /// Then
        XCTAssertEqual(settings2, [
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        ])

        /// Given/When
        let settings3 = SettingsDictionary()
            .swiftOptimizationLevel(.oSize)

        /// Then
        XCTAssertEqual(settings3, [
            "SWIFT_OPTIMIZATION_LEVEL": "-Osize",
        ])
    }

    func test_settingsDictionary_swiftObjcBridgingHeaderPath() {
        /// Given/When
        let settings = SettingsDictionary()
            .swiftObjcBridgingHeaderPath("/my/bridging/header/path.h")

        /// Then
        XCTAssertEqual(settings, [
            "SWIFT_OBJC_BRIDGING_HEADER": "/my/bridging/header/path.h",
        ])
    }

    func test_settingsDictionary_otherCFlags() {
        /// Given/When
        let settings = SettingsDictionary()
            .otherCFlags(["$(inherited)", "-my-c-flag"])

        /// Then
        XCTAssertEqual(settings, [
            "OTHER_CFLAGS": ["$(inherited)", "-my-c-flag"],
        ])
    }

    func test_settingsDictionary_otherLinkerFlags() {
        /// Given/When
        let settings = SettingsDictionary()
            .otherLinkerFlags(["$(inherited)", "-my-linker-flag"])

        /// Then
        XCTAssertEqual(settings, [
            "OTHER_LDFLAGS": ["$(inherited)", "-my-linker-flag"],
        ])
    }

    func test_settingsDictionary_SwiftOptimizeObjectLifetimes() {
        /// Given/When
        let settings1 = SettingsDictionary()
            .swiftOptimizeObjectLifetimes(true)

        /// Then
        XCTAssertEqual(settings1, [
            "SWIFT_OPTIMIZE_OBJECT_LIFETIME": "YES",
        ])

        /// Given/When
        let settings2 = SettingsDictionary()
            .swiftOptimizeObjectLifetimes(false)

        /// Then
        XCTAssertEqual(settings2, [
            "SWIFT_OPTIMIZE_OBJECT_LIFETIME": "NO",
        ])
    }

    func test_settingsDictionary_marketingVersion() {
        /// Given/When
        let settings = SettingsDictionary()
            .marketingVersion("1.0.0")

        /// Then
        XCTAssertEqual(settings, [
            "MARKETING_VERSION": "1.0.0",
        ])
    }

    func test_settingsDictionary_debugInformationFormat() {
        /// Given/When
        let settings1 = SettingsDictionary()
            .debugInformationFormat(.dwarf)

        /// Then
        XCTAssertEqual(settings1, [
            "DEBUG_INFORMATION_FORMAT": "dwarf",
        ])

        /// Given/When
        let settings2 = SettingsDictionary()
            .debugInformationFormat(.dwarfWithDsym)

        /// Then
        XCTAssertEqual(settings2, [
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        ])
    }

    func test_settingsDictionary_bundleDisplayName() {
        // Given/When
        let settings = SettingsDictionary()
            .bundleDisplayName("Some Application")

        /// Then
        XCTAssertEqual(settings, [
            "INFOPLIST_KEY_CFBundleDisplayName": "Some Application",
        ])
    }

    func test_settingsDictionary_applicationCategory() {
        /// Given/When
        let settings1 = SettingsDictionary()
            .applicationCategory(.business)

        /// Then
        XCTAssertEqual(settings1, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.business",
        ])

        /// Given/When
        let settings2 = SettingsDictionary()
            .applicationCategory(.developerTools)

        /// Then
        XCTAssertEqual(settings2, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.developer-tools",
        ])

        /// Given/When
        let settings3 = SettingsDictionary()
            .applicationCategory(.education)

        /// Then
        XCTAssertEqual(settings3, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.education",
        ])

        /// Given/When
        let settings4 = SettingsDictionary()
            .applicationCategory(.entertainment)

        /// Then
        XCTAssertEqual(settings4, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.entertainment",
        ])

        /// Given/When
        let settings5 = SettingsDictionary()
            .applicationCategory(.finance)

        /// Then
        XCTAssertEqual(settings5, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.finance",
        ])

        /// Given/When
        let settings6 = SettingsDictionary()
            .applicationCategory(.games)

        /// Then
        XCTAssertEqual(settings6, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.games",
        ])

        /// Given/When
        let settings7 = SettingsDictionary()
            .applicationCategory(.actionGames)

        /// Then
        XCTAssertEqual(settings7, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.action-games",
        ])

        /// Given/When
        let settings8 = SettingsDictionary()
            .applicationCategory(.adventureGames)

        /// Then
        XCTAssertEqual(settings8, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.adventure-games",
        ])

        /// Given/When
        let settings9 = SettingsDictionary()
            .applicationCategory(.arcadeGames)

        /// Then
        XCTAssertEqual(settings9, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.arcade-games",
        ])

        /// Given/When
        let settings10 = SettingsDictionary()
            .applicationCategory(.boardGames)

        /// Then
        XCTAssertEqual(settings10, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.board-games",
        ])

        /// Given/When
        let settings11 = SettingsDictionary()
            .applicationCategory(.cardGames)

        /// Then
        XCTAssertEqual(settings11, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.card-games",
        ])

        /// Given/When
        let settings12 = SettingsDictionary()
            .applicationCategory(.casinoGames)

        /// Then
        XCTAssertEqual(settings12, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.casino-games",
        ])

        /// Given/When
        let settings13 = SettingsDictionary()
            .applicationCategory(.diceGames)

        /// Then
        XCTAssertEqual(settings13, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.dice-games",
        ])

        /// Given/When
        let settings14 = SettingsDictionary()
            .applicationCategory(.educationalGames)

        /// Then
        XCTAssertEqual(settings14, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.educational-games",
        ])

        /// Given/When
        let settings15 = SettingsDictionary()
            .applicationCategory(.familyGames)

        /// Then
        XCTAssertEqual(settings15, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.family-games",
        ])

        /// Given/When
        let settings16 = SettingsDictionary()
            .applicationCategory(.kidsGames)

        /// Then
        XCTAssertEqual(settings16, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.kids-games",
        ])

        /// Given/When
        let settings17 = SettingsDictionary()
            .applicationCategory(.musicGames)

        /// Then
        XCTAssertEqual(settings17, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.music-games",
        ])

        /// Given/When
        let settings18 = SettingsDictionary()
            .applicationCategory(.puzzleGames)

        /// Then
        XCTAssertEqual(settings18, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.puzzle-games",
        ])

        /// Given/When
        let settings19 = SettingsDictionary()
            .applicationCategory(.racingGames)

        /// Then
        XCTAssertEqual(settings19, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.racing-games",
        ])

        /// Given/When
        let settings20 = SettingsDictionary()
            .applicationCategory(.rolePlayingGames)

        /// Then
        XCTAssertEqual(settings20, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.role-playing-games",
        ])

        /// Given/When
        let settings21 = SettingsDictionary()
            .applicationCategory(.simulationGames)

        /// Then
        XCTAssertEqual(settings21, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.simulation-games",
        ])

        /// Given/When
        let settings22 = SettingsDictionary()
            .applicationCategory(.sportsGames)

        /// Then
        XCTAssertEqual(settings22, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.sports-games",
        ])

        /// Given/When
        let settings23 = SettingsDictionary()
            .applicationCategory(.strategyGames)

        /// Then
        XCTAssertEqual(settings23, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.strategy-games",
        ])

        /// Given/When
        let settings24 = SettingsDictionary()
            .applicationCategory(.triviaGames)

        /// Then
        XCTAssertEqual(settings24, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.trivia-games",
        ])

        /// Given/When
        let settings25 = SettingsDictionary()
            .applicationCategory(.wordGames)

        /// Then
        XCTAssertEqual(settings25, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.word-games",
        ])

        /// Given/When
        let settings26 = SettingsDictionary()
            .applicationCategory(.graphicsDesign)

        /// Then
        XCTAssertEqual(settings26, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.graphics-design",
        ])

        /// Given/When
        let settings27 = SettingsDictionary()
            .applicationCategory(.healthcareFitness)

        /// Then
        XCTAssertEqual(settings27, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.healthcare-fitness",
        ])

        /// Given/When
        let settings28 = SettingsDictionary()
            .applicationCategory(.lifestyle)

        /// Then
        XCTAssertEqual(settings28, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.lifestyle",
        ])

        /// Given/When
        let settings29 = SettingsDictionary()
            .applicationCategory(.medical)

        /// Then
        XCTAssertEqual(settings29, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.medical",
        ])

        /// Given/When
        let settings30 = SettingsDictionary()
            .applicationCategory(.music)

        /// Then
        XCTAssertEqual(settings30, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.music",
        ])

        /// Given/When
        let settings31 = SettingsDictionary()
            .applicationCategory(.news)

        /// Then
        XCTAssertEqual(settings31, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.news",
        ])

        /// Given/When
        let settings32 = SettingsDictionary()
            .applicationCategory(.photography)

        /// Then
        XCTAssertEqual(settings32, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.photography",
        ])

        /// Given/When
        let settings33 = SettingsDictionary()
            .applicationCategory(.productivity)

        /// Then
        XCTAssertEqual(settings33, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
        ])

        /// Given/When
        let settings34 = SettingsDictionary()
            .applicationCategory(.reference)

        /// Then
        XCTAssertEqual(settings34, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.reference",
        ])

        /// Given/When
        let settings35 = SettingsDictionary()
            .applicationCategory(.socialNetworking)

        /// Then
        XCTAssertEqual(settings35, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.social-networking",
        ])

        /// Given/When
        let settings36 = SettingsDictionary()
            .applicationCategory(.sports)

        /// Then
        XCTAssertEqual(settings36, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.sports",
        ])

        /// Given/When
        let settings37 = SettingsDictionary()
            .applicationCategory(.travel)

        /// Then
        XCTAssertEqual(settings37, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.travel",
        ])

        /// Given/When
        let settings38 = SettingsDictionary()
            .applicationCategory(.utilities)

        /// Then
        XCTAssertEqual(settings38, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.utilities",
        ])

        /// Given/When
        let settings39 = SettingsDictionary()
            .applicationCategory(.video)

        /// Then
        XCTAssertEqual(settings39, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.video",
        ])

        /// Given/When
        let settings40 = SettingsDictionary()
            .applicationCategory(.weather)

        /// Then
        XCTAssertEqual(settings40, [
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.weather",
        ])
    }
}
