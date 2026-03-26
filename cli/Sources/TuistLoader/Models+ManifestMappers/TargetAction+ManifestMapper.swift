import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

// swiftlint:disable:next large_tuple
extension TuistCore.TargetScript {
    static func from(
        manifest: ProjectDescription.TargetScript,
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming
    ) async throws -> TuistCore.TargetScript {
        let name = manifest.name
        let order = TuistCore.TargetScript.Order.from(manifest: manifest.order)
        let tool = manifest.tool
        let path = try manifest.path.map { try generatorPaths.resolve(path: $0) }
        let arguments = manifest.arguments
        let inputPaths = try await absolutePaths(
            for: manifest.inputPaths,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )
        .map(\.pathString)
        let inputFileListPaths = try manifest.inputFileListPaths.map { try generatorPaths.resolve(path: $0) }
        let outputPaths = try await absoluteOutputPaths(
            for: manifest.outputPaths,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )
        .map(\.pathString)
        let outputFileListPaths = try manifest.outputFileListPaths.map { try generatorPaths.resolve(path: $0) }
        let basedOnDependencyAnalysis = manifest.basedOnDependencyAnalysis
        let runForInstallBuildsOnly = manifest.runForInstallBuildsOnly
        let shellPath = manifest.shellPath
        let dependencyFile = try manifest.dependencyFile.map { try generatorPaths.resolve(path: $0) }

        return TargetScript(
            name: name,
            order: order,
            tool: tool,
            path: path,
            arguments: arguments,
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

    // MARK: - Private

    /// Resolves absolute paths for **input** paths — these use glob expansion so only existing
    /// files are included (standard behaviour for inputs).
    private static func absolutePaths(
        for paths: [ProjectDescription.Path],
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming
    ) async throws -> [AbsolutePath] {
        try await paths.concurrentMap { (path: ProjectDescription.Path) -> [AbsolutePath] in
            // Avoid globbing paths that contain build-variable references like $(SRCROOT).
            if path.pathString.contains("$") {
                return [try generatorPaths.resolve(path: path)]
            }
            let absolutePath = try generatorPaths.resolve(path: path)
            let base = try AbsolutePath(validating: absolutePath.dirname)
            let result = try await fileSystem.glob(directory: base, include: [absolutePath.basename]).collect()
            return result
        }.reduce([], +)
    }

    /// Resolves absolute paths for **output** paths.
    ///
    /// Unlike input paths, output files frequently do not yet exist on disk at project-generation
    /// time — they are created by the build phase script itself.  Globbing would silently drop
    /// every such path, which is the root cause of issue #5925.
    ///
    /// This function therefore **skips the glob step** and resolves each output path directly,
    /// regardless of whether the file currently exists on disk.  Paths that contain build-variable
    /// references (e.g. `$(DERIVED_FILE_DIR)/Foo.swift`) are also passed through as-is, matching
    /// the behaviour that was already in place for those paths.
    private static func absoluteOutputPaths(
        for paths: [ProjectDescription.Path],
        generatorPaths: GeneratorPaths,
        fileSystem _: FileSysteming
    ) async throws -> [AbsolutePath] {
        try paths.map { path in
            // Resolve the path regardless of whether the file exists.
            // Build-variable paths (containing "$") are resolved identically — the resolver
            // already handles them without touching the filesystem.
            try generatorPaths.resolve(path: path)
        }
    }
}

extension TuistCore.TargetScript.Order {
    static func from(manifest: ProjectDescription.TargetScript.Order) -> TuistCore.TargetScript.Order {
        switch manifest {
        case .pre:
            return .pre
        case .post:
            return .post
        }
    }
}
