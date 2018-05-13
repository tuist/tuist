import Basic
import Foundation
@testable import xcbuddykit

extension Configuration {
    static func test(settings: [String: String] = [:],
                     xcconfig: AbsolutePath? = AbsolutePath("/Config.xcconfig")) -> Configuration {
        return Configuration(settings: settings,
                             xcconfig: xcconfig)
    }
}

extension Settings {
    static func test(base: [String: String] = [:],
                     debug: Configuration? = Configuration(xcconfig: AbsolutePath("/Debug.xcconfig")),
                     release: Configuration? = Configuration(xcconfig: AbsolutePath("/Debug.xcconfig"))) -> Settings {
        return Settings(base: base,
                        debug: debug,
                        release: release)
    }
}
