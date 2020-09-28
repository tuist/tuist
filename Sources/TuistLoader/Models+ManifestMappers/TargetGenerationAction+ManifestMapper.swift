import Foundation

import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.TargetGenerationAction {
    /// Maps a ProjectDescription.TargetGenerationAction instance into a TuistCore.TargetGenerationAction model.
    /// - Parameters:
    ///   - manifest: Manifest representation of target action.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TargetGenerationAction, generatorPaths: GeneratorPaths) throws -> TuistCore.TargetGenerationAction {
        let tool = manifest.tool
        let order = TuistCore.TargetGenerationAction.Order.from(manifest: manifest.order)
        let arguments = manifest.arguments
        let path = try manifest.path.map { try generatorPaths.resolve(path: $0) }
        return TargetGenerationAction(order: order, tool: tool, path: path, arguments: arguments)
    }
}

extension TuistCore.TargetGenerationAction.Order {
    /// Maps a ProjectDescription.TargetGenerationAction.Order instance into a TuistCore.TargetGenerationAction.Order model.
    /// - Parameters:
    ///   - manifest: Manifest representation of target action order.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TargetGenerationAction.Order) -> TuistCore.TargetGenerationAction.Order {
        switch manifest {
        case .pre:
            return .pre
        case .post:
            return .post
        }
    }
}
