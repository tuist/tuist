import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import XcodeProjectGenerator
import TuistSupport

extension XcodeProjectGenerator.Configuration {
    /// Maps a ProjectDescription.Configuration instance into a XcodeProjectGenerator.Configuration instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of configuration.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.Configuration?,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeProjectGenerator.Configuration? {
        guard let manifest else { return nil }
        let settings = manifest.settings.mapValues(XcodeProjectGenerator.SettingValue.from)
        let xcconfig = try manifest.xcconfig.flatMap { try generatorPaths.resolve(path: $0) }
        return Configuration(settings: settings, xcconfig: xcconfig)
    }
}
