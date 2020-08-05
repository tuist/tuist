import Foundation
import TSCBasic
@testable import TuistCore

public extension Configuration {
    static func test(settings: SettingsDictionary = [:],
                     xcconfig: AbsolutePath? = AbsolutePath("/Config.xcconfig")) -> Configuration
    {
        Configuration(settings: settings, xcconfig: xcconfig)
    }
}

public extension Settings {
    static func test(base: SettingsDictionary = [:],
                     debug: Configuration = Configuration(settings: [:], xcconfig: AbsolutePath("/Debug.xcconfig")),
                     release: Configuration = Configuration(settings: [:], xcconfig: AbsolutePath("/Release.xcconfig"))) -> Settings
    {
        Settings(base: base,
                 configurations: [.debug: debug, .release: release])
    }

    static func test(base: SettingsDictionary = [:],
                     configurations: [BuildConfiguration: Configuration?] = [:]) -> Settings
    {
        Settings(base: base, configurations: configurations)
    }

    static func test(defaultSettings: DefaultSettings) -> Settings {
        Settings(base: [:],
                 configurations: [.debug: Configuration(settings: [:]),
                                  .release: Configuration(settings: [:])],
                 defaultSettings: defaultSettings)
    }
}
