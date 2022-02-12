import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.Configuration {
    /// Maps a ProjectDescription.Configuration instance into a TuistGraph.Configuration instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of configuration.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.Configuration?,
        generatorPaths: GeneratorPaths
    ) throws -> TuistGraph.Configuration? {
        guard let manifest = manifest else { return nil }
        let settings = manifest.settings.mapValues(TuistGraph.SettingValue.from)
        let xcconfig = try manifest.xcconfig.flatMap { try generatorPaths.resolve(path: $0) }
        return Configuration(settings: settings, xcconfig: xcconfig)
    }
}
