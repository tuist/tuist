import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.TargetAction {
    static func from(manifest: ProjectDescription.TargetAction,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.TargetAction {
        let name = manifest.name
        let tool = manifest.tool
        let order = TuistCore.TargetAction.Order.from(manifest: manifest.order)
        let arguments = manifest.arguments
        let inputPaths = try manifest.inputPaths.map { try generatorPaths.resolve(path: $0) }
        let inputFileListPaths = try manifest.inputFileListPaths.map { try generatorPaths.resolve(path: $0) }
        let outputPaths = try manifest.outputPaths.map { try generatorPaths.resolve(path: $0) }
        let outputFileListPaths = try manifest.outputFileListPaths.map { try generatorPaths.resolve(path: $0) }
        let path = try manifest.path.map { try generatorPaths.resolve(path: $0) }
        return TargetAction(name: name,
                            order: order,
                            tool: tool,
                            path: path,
                            arguments: arguments,
                            inputPaths: inputPaths,
                            inputFileListPaths: inputFileListPaths,
                            outputPaths: outputPaths,
                            outputFileListPaths: outputFileListPaths)
    }
}

extension TuistCore.TargetAction.Order {
    static func from(manifest: ProjectDescription.TargetAction.Order) -> TuistCore.TargetAction.Order {
        switch manifest {
        case .pre:
            return .pre
        case .post:
            return .post
        }
    }
}
