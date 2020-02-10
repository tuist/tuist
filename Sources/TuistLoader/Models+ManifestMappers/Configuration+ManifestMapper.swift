import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.Configuration {
    /// Maps a ProjectDescription.Configuration instance into a TuistCore.Configuration instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of configuration.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Configuration,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.Configuration? {
        let settings = manifest.settings.mapValues(TuistCore.SettingValue.from)
        let xcconfig = try manifest.xcconfig.flatMap { try generatorPaths.resolve(path: $0) }
        return Configuration(settings: settings, xcconfig: xcconfig)
    }
}
