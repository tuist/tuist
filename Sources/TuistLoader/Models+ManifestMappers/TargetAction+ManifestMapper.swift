import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.TargetAction {
    /// Maps a ProjectDescription.TargetAction instance into a TuistGraph.TargetAction model.
    /// - Parameters:
    ///   - manifest: Manifest representation of target action.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TargetAction, generatorPaths: GeneratorPaths) throws -> TuistGraph.TargetAction {
        let name = manifest.name
        let order = TuistGraph.TargetAction.Order.from(manifest: manifest.order)
        let inputPaths = try absolutePaths(for: manifest.inputPaths, generatorPaths: generatorPaths)
        let inputFileListPaths = try absolutePaths(for: manifest.inputFileListPaths, generatorPaths: generatorPaths)
        let outputPaths = try absolutePaths(for: manifest.outputPaths, generatorPaths: generatorPaths)
        let outputFileListPaths = try absolutePaths(for: manifest.outputFileListPaths, generatorPaths: generatorPaths)
        let basedOnDependencyAnalysis = manifest.basedOnDependencyAnalysis
        let runForInstallBuildsOnly = manifest.runForInstallBuildsOnly
        
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
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly
        )
    }

    private static func absolutePaths(for paths: [Path], generatorPaths: GeneratorPaths) throws -> [AbsolutePath] {
        try paths.map { (path: Path) -> [AbsolutePath] in
            // avoid globbing paths that contain variables
            if path.pathString.contains("$") {
                return [try generatorPaths.resolve(path: path)]
            }
            let absolutePath = try generatorPaths.resolve(path: path)
            let base = AbsolutePath(absolutePath.dirname)
            return try base.throwingGlob(absolutePath.basename)
        }.reduce([], +)
    }
}

extension TuistGraph.TargetAction.Order {
    /// Maps a ProjectDescription.TargetAction.Order instance into a TuistGraph.TargetAction.Order model.
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
