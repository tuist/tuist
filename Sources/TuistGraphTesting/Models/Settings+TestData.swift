import Foundation
import TSCBasic
@testable import TuistGraph

extension Configuration {
    public static func test(
        settings: SettingsDictionary = [:],
        xcconfig: AbsolutePath? = AbsolutePath("/Config.xcconfig")
    ) -> Configuration {
        Configuration(settings: settings, xcconfig: xcconfig)
    }
}

extension Settings {
    public static func test(
        base: SettingsDictionary = [:],
        debug: Configuration = Configuration(settings: [:], xcconfig: AbsolutePath("/Debug.xcconfig")),
        release: Configuration = Configuration(settings: [:], xcconfig: AbsolutePath("/Release.xcconfig"))
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
