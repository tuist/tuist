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
        let inputPaths = try await fileListGlobStrings(
            for: manifest.inputPaths,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )
        let inputFileListPaths = try await pathStrings(
            for: manifest.inputFileListPaths,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )
        let outputPaths = try await pathStrings(
            for: manifest.outputPaths,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )
        let outputFileListPaths = try await pathStrings(
            for: manifest.outputFileListPaths,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )
        let basedOnDependencyAnalysis = manifest.basedOnDependencyAnalysis
        let runForInstallBuildsOnly = manifest.runForInstallBuildsOnly
        let shellPath = manifest.shellPath

        let dependencyFile: AbsolutePath?

        if let manifestDependencyFile = manifest.dependencyFile {
            dependencyFile = try generatorPaths.resolve(path: manifestDependencyFile)
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

    private static func fileListGlobStrings(
        for globs: [FileListGlob],
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming
    ) async throws -> [String] {
        try await globs.concurrentMap { (glob: FileListGlob) -> [String] in
            let path = glob.glob

            // If it's a glob pattern with excludes, use the unfold method
            if !glob.excluding.isEmpty || fileSystem.isGlobPattern(path) {
                let unfolded = try await glob.unfold(
                    generatorPaths: generatorPaths,
                    fileSystem: fileSystem
                )

                // For relativeToManifest paths, convert back to relative paths
                if path.type == .relativeToManifest {
                    return unfolded.map { $0.relative(to: generatorPaths.manifestDirectory).pathString }
                } else {
                    return unfolded.map(\.pathString)
                }
            }

            return try await resolvePathStrings(
                path: path,
                generatorPaths: generatorPaths,
                fileSystem: fileSystem
            )
        }.reduce([], +)
    }

    private static func pathStrings(
        for paths: [Path],
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming
    ) async throws -> [String] {
        try await paths.concurrentMap { (path: Path) -> [String] in
            try await resolvePathStrings(
                path: path,
                generatorPaths: generatorPaths,
                fileSystem: fileSystem
            )
        }.reduce([], +)
    }

    private static func resolvePathStrings(
        path: Path,
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming
    ) async throws -> [String] {
        // For relativeToManifest paths that are not glob patterns, keep them as strings
        if path.type == .relativeToManifest, !fileSystem.isGlobPattern(path) {
            return [path.pathString]
        }

        // avoid globbing paths that contain variables
        if path.pathString.contains("$") {
            return [path.pathString]
        }

        // Avoid globbing paths that are not glob patterns.
        // More than that - globbing requires the path to be existing at the moment of the globbing
        // which is not always the case.
        // For example, output paths of a script that are not created yet.
        if !fileSystem.isGlobPattern(path) {
            return [try generatorPaths.resolve(path: path).pathString]
        }

        let absolutePath = try generatorPaths.resolve(path: path)
        let base = try AbsolutePath(validating: absolutePath.dirname)
        let globResults = try await fileSystem.glob(directory: base, include: [absolutePath.basename]).collect()

        // For relativeToManifest paths, convert back to relative paths
        if path.type == .relativeToManifest {
            return globResults.map { $0.relative(to: generatorPaths.manifestDirectory).pathString }
        } else {
            return globResults.map(\.pathString)
        }
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
