import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.TargetAction {
    /// Maps a ProjectDescription.TargetAction instance into a TuistCore.TargetAction model.
    /// - Parameters:
    ///   - manifest: Manifest representation of target action.
    ///   - pathResolver: A path resolver.
    static func from(manifest: ProjectDescription.TargetAction, generatorPaths: GeneratorPaths) throws -> TuistCore.TargetAction {
        let name = manifest.name
        let tool = manifest.tool
        let order = TuistCore.TargetAction.Order.from(manifest: manifest.order)
        let arguments = manifest.arguments
        let inputPaths = try manifest.inputPaths.map { try generatorPaths.resolve(path: $0) }
        let inputFileListPaths = try manifest.inputFileListPaths.map { try generatorPaths.resolve(path: $0) }
        let outputPaths = try manifest.outputPaths.map { try generatorPaths.resolve(path: $0) }
        let outputFileListPaths = try manifest.outputFileListPaths.map { try generatorPaths.resolve(path: $0) }
        let basedOnDependencyAnalysis = manifest.basedOnDependencyAnalysis
        let path = try manifest.path.map { try generatorPaths.resolve(path: $0) }
        return TargetAction(name: name,
                            order: order,
                            tool: tool,
                            path: path,
                            arguments: arguments,
                            inputPaths: inputPaths,
                            inputFileListPaths: inputFileListPaths,
                            outputPaths: outputPaths,
                            outputFileListPaths: outputFileListPaths,
                            basedOnDependencyAnalysis: basedOnDependencyAnalysis)
    }
}

extension TuistCore.TargetAction.Order {
    /// Maps a ProjectDescription.TargetAction.Order instance into a TuistCore.TargetAction.Order model.
    /// - Parameters:
    ///   - manifest: Manifest representation of target action order.
    ///   - pathResolver: Generator paths.
    static func from(manifest: ProjectDescription.TargetAction.Order) -> TuistCore.TargetAction.Order {
        switch manifest {
        case .pre:
            return .pre
        case .post:
            return .post
        }
    }
}
