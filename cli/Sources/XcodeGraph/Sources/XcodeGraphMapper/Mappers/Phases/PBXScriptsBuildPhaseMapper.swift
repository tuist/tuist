import Foundation
import Path
import XcodeGraph
import XcodeProj

/// A protocol for mapping PBXShellScriptBuildPhases into domain models.
protocol PBXScriptsBuildPhaseMapping {
    /// Maps the given script phases into `TargetScript` models.
    ///
    /// - Parameters:
    ///   - scriptPhases: The shell script build phases to convert.
    ///   - buildPhases: The full list of a target's `PBXBuildPhase`s, used to determine script order.
    /// - Returns: An array of `TargetScript` models representing each shell script build phase.
    /// - Throws: If any file paths cannot be validated.
    func map(
        _ scriptPhases: [PBXShellScriptBuildPhase],
        buildPhases: [PBXBuildPhase]
    ) throws -> [TargetScript]

    /// Maps shell script build phases into a simpler, “raw” representation (`RawScriptBuildPhase`).
    ///
    /// - Parameter scriptPhases: The shell script build phases to map.
    /// - Returns: A list of `RawScriptBuildPhase` models for each script.
    func mapRawScriptBuildPhases(_ scriptPhases: [PBXShellScriptBuildPhase]) -> [RawScriptBuildPhase]
}

/// Maps `PBXShellScriptBuildPhase` instances into `TargetScript` and `RawScriptBuildPhase` models.
struct PBXScriptsBuildPhaseMapper: PBXScriptsBuildPhaseMapping {
    func map(
        _ scriptPhases: [PBXShellScriptBuildPhase],
        buildPhases: [PBXBuildPhase]
    ) throws -> [TargetScript] {
        try scriptPhases.compactMap {
            try mapScriptPhase($0, buildPhases: buildPhases)
        }
    }

    func mapRawScriptBuildPhases(_ scriptPhases: [PBXShellScriptBuildPhase]) -> [RawScriptBuildPhase] {
        scriptPhases.map { mapShellScriptBuildPhase($0) }
    }

    // MARK: - Private Helpers

    /// Converts a single `PBXShellScriptBuildPhase` to a `TargetScript`, if valid.
    private func mapScriptPhase(
        _ scriptPhase: PBXShellScriptBuildPhase,
        buildPhases: [PBXBuildPhase]
    ) throws -> TargetScript? {
        guard let shellScript = scriptPhase.shellScript else {
            return nil
        }

        let dependencyFile = try scriptPhase.dependencyFile.map {
            try AbsolutePath(validating: $0)
        }

        return TargetScript(
            name: scriptPhase.name ?? BuildPhaseConstants.defaultScriptName,
            order: determineScriptOrder(buildPhases: buildPhases, scriptPhase: scriptPhase),
            script: .embedded(shellScript),
            inputPaths: scriptPhase.inputPaths,
            inputFileListPaths: scriptPhase.inputFileListPaths ?? [],
            outputPaths: scriptPhase.outputPaths,
            outputFileListPaths: scriptPhase.outputFileListPaths ?? [],
            showEnvVarsInLog: scriptPhase.showEnvVarsInLog,
            basedOnDependencyAnalysis: scriptPhase.alwaysOutOfDate ? false : nil,
            runForInstallBuildsOnly: scriptPhase.runOnlyForDeploymentPostprocessing,
            shellPath: scriptPhase.shellPath ?? BuildPhaseConstants.defaultShellPath,
            dependencyFile: dependencyFile
        )
    }

    /// Converts a single `PBXShellScriptBuildPhase` into a simpler `RawScriptBuildPhase`.
    private func mapShellScriptBuildPhase(
        _ buildPhase: PBXShellScriptBuildPhase
    ) -> RawScriptBuildPhase {
        let name = buildPhase.name() ?? BuildPhaseConstants.unnamedScriptPhase
        let shellPath = buildPhase.shellPath ?? BuildPhaseConstants.defaultShellPath
        let script = buildPhase.shellScript ?? ""
        let showEnvVarsInLog = buildPhase.showEnvVarsInLog

        return RawScriptBuildPhase(
            name: name,
            script: script,
            showEnvVarsInLog: showEnvVarsInLog,
            hashable: false,
            shellPath: shellPath
        )
    }

    /// Determines the order of the script relative to other build phases (pre or post sources).
    private func determineScriptOrder(
        buildPhases: [PBXBuildPhase],
        scriptPhase: PBXShellScriptBuildPhase
    ) -> TargetScript.Order {
        guard let scriptIndex = buildPhases.firstIndex(of: scriptPhase) else {
            return .pre
        }

        // If we have a Sources phase, check whether this script is above or below it.
        if let sourcesIndex = buildPhases.firstIndex(where: { $0.buildPhase == .sources }) {
            return scriptIndex > sourcesIndex ? .post : .pre
        }

        // Fallback: if it's at index 0, consider it pre; otherwise post.
        return scriptIndex == 0 ? .pre : .post
    }
}
