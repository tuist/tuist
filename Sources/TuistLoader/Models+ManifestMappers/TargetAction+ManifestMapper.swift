import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.TargetAction {
    /// Maps a ProjectDescription.TargetAction instance into a TuistCore.TargetAction model.
    /// - Parameters:
    ///   - manifest: Manifest representation of target action.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TargetAction, generatorPaths: GeneratorPaths) throws -> TuistGraph.TargetAction {
        let name = manifest.name
        let order = TuistGraph.TargetAction.Order.from(manifest: manifest.order)
        let inputPaths = try manifest.inputPaths.map { try generatorPaths.resolve(path: $0) }
        let inputFileListPaths = try manifest.inputFileListPaths.map { try generatorPaths.resolve(path: $0) }
        let outputPaths = try manifest.outputPaths.map { try generatorPaths.resolve(path: $0) }
        let outputFileListPaths = try manifest.outputFileListPaths.map { try generatorPaths.resolve(path: $0) }
        let basedOnDependencyAnalysis = manifest.basedOnDependencyAnalysis

        let script: TuistGraph.TargetAction.Script
        switch manifest.script {
        case let .embedded(text):
            script = .embedded(text)

        case let .scriptPath(path, arguments):
            let scriptPath = try generatorPaths.resolve(path: path)
            script = .scriptPath(scriptPath, args: arguments)

        case let .tool(tool, arguments):
            script = .tool(tool, arguments)
        }

        return TargetAction(
            name: name,
            order: order,
            script: script,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis
        )
    }
}

extension TuistGraph.TargetAction.Order {
    /// Maps a ProjectDescription.TargetAction.Order instance into a TuistCore.TargetAction.Order model.
    /// - Parameters:
    ///   - manifest: Manifest representation of target action order.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TargetAction.Order) -> TuistGraph.TargetAction.Order {
        switch manifest {
        case .pre:
            return .pre
        case .post:
            return .post
        }
    }
}
