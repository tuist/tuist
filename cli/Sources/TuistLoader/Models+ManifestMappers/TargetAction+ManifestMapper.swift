import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.TargetScript {
    /// Maps a ProjectDescription.TargetAction instance into a XcodeGraph.TargetAction model.
    /// - Parameters:
    ///   - manifest: Manifest representation of target action.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.TargetScript,
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming
    ) async throws -> XcodeGraph
        .TargetScript
    {
        let name = manifest.name
        let order = XcodeGraph.TargetScript.Order.from(manifest: manifest.order)
        let inputPaths = try await manifest.inputPaths
            .concurrentCompactMap {
                try await $0.unfold(
                    generatorPaths: generatorPaths,
                    fileSystem: fileSystem
                )
            }
            .flatMap { $0 }
            .map(\.pathString)
        let inputFileListPaths = try await absolutePaths(
            for: manifest.inputFileListPaths,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )
        .map(\.pathString)
        let outputPaths = try await absolutePaths(
            for: manifest.outputPaths,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )
        .map(\.pathString)
        let outputFileListPaths = try await absolutePaths(
            for: manifest.outputFileListPaths,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )
        .map(\.pathString)
        let basedOnDependencyAnalysis = manifest.basedOnDependencyAnalysis
        let runForInstallBuildsOnly = manifest.runForInstallBuildsOnly
        let shellPath = manifest.shellPath

        let dependencyFile: AbsolutePath?

        if let manifestDependencyFile = manifest.dependencyFile {
            dependencyFile = try await absolutePaths(
                for: [manifestDependencyFile],
                generatorPaths: generatorPaths,
                fileSystem: fileSystem
            ).first
        } else {
            dependencyFile = nil
        }

        let script: XcodeGraph.TargetScript.Script
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

    private static func absolutePaths(
        for paths: [Path],
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming
    ) async throws -> [AbsolutePath] {
        try await paths.concurrentMap { (path: Path) -> [AbsolutePath] in
            // avoid globbing paths that contain variables
            if path.pathString.contains("$") {
                return [try generatorPaths.resolve(path: path)]
            }
            // Avoid globbing paths that are not glob patterns.
            // More than that - globbing requires the path to be existing at the moment of the globbing
            // which is not always the case.
            // For example, output paths of a script that are not created yet.
            if !isGlobPattern(path) {
                return [try generatorPaths.resolve(path: path)]
            }

            let absolutePath = try generatorPaths.resolve(path: path)
            let base = try AbsolutePath(validating: absolutePath.dirname)
            return try await fileSystem.glob(directory: base, include: [absolutePath.basename]).collect()
        }.reduce([], +)
    }

    private static func isGlobPattern(_ path: Path) -> Bool {
        let pathString = path.pathString
        return pathString.contains("*") || pathString.contains("?") || pathString.contains("[")
    }
}

extension XcodeGraph.TargetScript.Order {
    /// Maps a ProjectDescription.TargetAction.Order instance into a XcodeGraph.TargetAction.Order model.
    /// - Parameters:
    ///   - manifest: Manifest representation of target action order.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TargetScript.Order) -> XcodeGraph.TargetScript.Order {
        switch manifest {
        case .pre:
            return .pre
        case .post:
            return .post
        }
    }
}
