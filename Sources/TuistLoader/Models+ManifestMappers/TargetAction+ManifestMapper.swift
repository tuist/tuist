import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.TargetScript {
    /// Maps a ProjectDescription.TargetAction instance into a TuistGraph.TargetAction model.
    /// - Parameters:
    ///   - manifest: Manifest representation of target action.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TargetScript, generatorPaths: GeneratorPaths) throws -> TuistGraph
        .TargetScript
    {
        let name = manifest.name
        let order = TuistGraph.TargetScript.Order.from(manifest: manifest.order)
        let inputPaths = try absolutePaths(for: manifest.inputPaths, generatorPaths: generatorPaths)
        let inputFileListPaths = try absolutePaths(for: manifest.inputFileListPaths, generatorPaths: generatorPaths)
        let outputPaths = try absolutePaths(for: manifest.outputPaths, generatorPaths: generatorPaths)
        let outputFileListPaths = try absolutePaths(for: manifest.outputFileListPaths, generatorPaths: generatorPaths)
        let basedOnDependencyAnalysis = manifest.basedOnDependencyAnalysis
        let runForInstallBuildsOnly = manifest.runForInstallBuildsOnly
        let shellPath = manifest.shellPath

        let dependencyFile: AbsolutePath?

        if let manifestDependencyFile = manifest.dependencyFile {
            dependencyFile = try absolutePaths(for: [manifestDependencyFile], generatorPaths: generatorPaths).first
        } else {
            dependencyFile = nil
        }

        let script: TuistGraph.TargetScript.Script
        switch manifest.script {
        case let .embedded(text):
            script = .embedded(text)

        case let .scriptPath(path, arguments):
            let scriptPath = try generatorPaths.resolve(path: path)
            script = .scriptPath(path: scriptPath, args: arguments)

        case let .tool(tool, arguments):
            script = .tool(path: tool, args: arguments)
        }

        return TargetScript(
            name: name,
            order: order,
            script: script,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly,
            shellPath: shellPath,
            dependencyFile: dependencyFile
        )
    }

    private static func absolutePaths(for paths: [Path], generatorPaths: GeneratorPaths) throws -> [AbsolutePath] {
        try paths.map { (path: Path) -> [AbsolutePath] in
            // avoid globbing paths that contain variables
            if path.pathString.contains("$") {
                return [try generatorPaths.resolve(path: path)]
            }
            let absolutePath = try generatorPaths.resolve(path: path)
            let base = try AbsolutePath(validating: absolutePath.dirname)
            return try base.throwingGlob(absolutePath.basename)
        }.reduce([], +)
    }
}

extension TuistGraph.TargetScript.Order {
    /// Maps a ProjectDescription.TargetAction.Order instance into a TuistGraph.TargetAction.Order model.
    /// - Parameters:
    ///   - manifest: Manifest representation of target action order.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TargetScript.Order) -> TuistGraph.TargetScript.Order {
        switch manifest {
        case .pre:
            return .pre
        case .post:
            return .post
        }
    }
}
