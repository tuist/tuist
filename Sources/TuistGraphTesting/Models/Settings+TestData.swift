import Foundation
import TSCBasic
@testable import TuistGraph

extension Configuration {
    public static func test(
        settings: SettingsDictionary = [:],
        xcconfig: AbsolutePath? = try! AbsolutePath(validating: "/Config.xcconfig") // swiftlint:disable:this force_try
    ) -> Configuration {
        Configuration(settings: settings, xcconfig: xcconfig)
    }
}

extension Settings {
    public static func test(
        base: SettingsDictionary = [:],
        // swiftlint:disable:next force_try
        debug: Configuration = Configuration(settings: [:], xcconfig: try! AbsolutePath(validating: "/Debug.xcconfig")),
        // swiftlint:disable:next force_try
        release: Configuration = Configuration(settings: [:], xcconfig: try! AbsolutePath(validating: "/Release.xcconfig"))
    ) -> Settings {
        Settings(
            base: base,
            configurations: [.debug: debug, .release: release]
        )
    }

    public static func test(
        base: SettingsDictionary = [:],
        configurations: [BuildConfiguration: Configuration?] = [:]
    ) -> Settings {
        Settings(base: base, configurations: configurations)
    }

    public static func test(defaultSettings: DefaultSettings) -> Settings {
        Settings(
            base: [:],
            configurations: [
                .debug: Configuration(settings: [:]),
                .release: Configuration(settings: [:]),
            ],
            defaultSettings: defaultSettings
        )
    }
}
