import Basic
import Foundation
@testable import TuistKit

extension Configuration {
    static func test(settings: [String: String] = [:],
                     xcconfig: AbsolutePath? = AbsolutePath("/Config.xcconfig")) -> Configuration {
        return Configuration(name: "Test", buildConfiguration: .debug, settings: settings, xcconfig: xcconfig)
    }
}

extension Settings {
    static func test(base: [String: String] = [:],
                     debug: Configuration = Configuration(name: "Debug", buildConfiguration: .debug, xcconfig: AbsolutePath("/Debug.xcconfig")),
                     release: Configuration = Configuration(name: "Release", buildConfiguration: .release, xcconfig: AbsolutePath("/Release.xcconfig"))
    ) -> Settings {
        return Settings(base: base, configurations: [debug, release])
    }
}

extension TargetSettings {
    static func test(base: BuildSettings = [:], buildSettings: [Configuration.Name: BuildSettings] = [:]) -> TargetSettings {
        return TargetSettings(base: base, buildSettings: buildSettings)
    }
}
