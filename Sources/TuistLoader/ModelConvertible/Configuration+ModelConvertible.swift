import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Configuration: ModelConvertible {
    init(manifest: ProjectDescription.Configuration, generatorPaths: GeneratorPaths) throws {
        let settings = try manifest.settings.mapValues { try TuistCore.SettingValue(manifest: $0, generatorPaths: generatorPaths) }
        let xcconfig = try manifest.xcconfig.flatMap { try generatorPaths.resolve(path: $0) }
        self.init(settings: settings, xcconfig: xcconfig)
    }
}
