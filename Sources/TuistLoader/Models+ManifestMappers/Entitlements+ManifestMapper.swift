import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.Entitlements {
    /// Maps a ProjectDescription.Entitlements instance into a XcodeProjectGenerator.Entitlements instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the Entitlements model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Entitlements?, generatorPaths: GeneratorPaths) throws -> XcodeProjectGenerator
        .Entitlements?
    {
        switch manifest {
        case let .file(infoplistPath):
            return .file(path: try generatorPaths.resolve(path: infoplistPath))
        case let .dictionary(dictionary):
            return .dictionary(
                dictionary.mapValues { XcodeProjectGenerator.Plist.Value.from(manifest: $0) }
            )
        case let .variable(setting):
            return .variable(setting)
        case .none:
            return .none
        }
    }
}
