import Basic
import Foundation
@testable import TuistGenerator

extension Configuration {
    static func test(settings: [String: SettingValue] = [:],
                     xcconfig: AbsolutePath? = AbsolutePath("/Config.xcconfig")) -> Configuration {
        return Configuration(settings: settings, xcconfig: xcconfig)
    }
}

extension Settings {
    static func test(base: [String: SettingValue] = [:],
                     debug: Configuration = Configuration(settings: [:], xcconfig: AbsolutePath("/Debug.xcconfig")),
                     release: Configuration = Configuration(settings: [:], xcconfig: AbsolutePath("/Release.xcconfig"))) -> Settings {
        return Settings(base: base,
                        configurations: [.debug: debug, .release: release])
    }

    static func test(base: [String: SettingValue] = [:],
                     configurations: [BuildConfiguration: Configuration?] = [:]) -> Settings {
        return Settings(base: base, configurations: configurations)
    }
}
