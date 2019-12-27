import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.TargetAction: ModelConvertible {
    init(manifest: ProjectDescription.TargetAction, generatorPaths: GeneratorPaths) throws {
        let name = manifest.name
        let tool = manifest.tool
        let order = try TuistCore.TargetAction.Order(manifest: manifest.order, generatorPaths: generatorPaths)
        let arguments = manifest.arguments
        let inputPaths = try manifest.inputPaths.map { try generatorPaths.resolve(path: $0) }
        let inputFileListPaths = try manifest.inputFileListPaths.map { try generatorPaths.resolve(path: $0) }
        let outputPaths = try manifest.outputPaths.map { try generatorPaths.resolve(path: $0) }
        let outputFileListPaths = try manifest.outputFileListPaths.map { try generatorPaths.resolve(path: $0) }
        let path = try manifest.path.map { try generatorPaths.resolve(path: $0) }
        self.init(name: name,
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

extension TuistCore.TargetAction.Order: ModelConvertible {
    init(manifest: ProjectDescription.TargetAction.Order, generatorPaths _: GeneratorPaths) throws {
        switch manifest {
        case .pre:
            self = .pre
        case .post:
            self = .post
        }
    }
}
