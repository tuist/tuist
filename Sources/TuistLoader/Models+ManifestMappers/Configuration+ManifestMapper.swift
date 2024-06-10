import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.Configuration {
    /// Maps a ProjectDescription.Configuration instance into a XcodeGraph.Configuration instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of configuration.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.Configuration?,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.Configuration? {
        guard let manifest else { return nil }
        let settings = manifest.settings.mapValues(XcodeGraph.SettingValue.from)
        let xcconfig = try manifest.xcconfig.flatMap { try generatorPaths.resolve(path: $0) }
        return Configuration(settings: settings, xcconfig: xcconfig)
    }
}
