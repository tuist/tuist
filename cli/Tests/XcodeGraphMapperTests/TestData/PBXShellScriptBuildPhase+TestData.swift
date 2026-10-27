import XcodeProj

extension PBXShellScriptBuildPhase {
    static func test(
        files: [PBXBuildFile] = [],
        name: String? = "Embed Precompiled Frameworks",
        shellScript: String = "#!/bin/sh\necho 'Mock Shell Script'",
        inputPaths: [String] = [],
        outputPaths: [String] = [],
        inputFileListPaths: [String]? = nil,
        outputFileListPaths: [String]? = nil,
        shellPath: String = "/bin/sh",
        buildActionMask: UInt = PBXBuildPhase.defaultBuildActionMask,
        runOnlyForDeploymentPostprocessing: Bool = false,
        showEnvVarsInLog: Bool = true,
        alwaysOutOfDate: Bool = false,
        dependencyFile: String? = nil
    ) -> PBXShellScriptBuildPhase {
        PBXShellScriptBuildPhase(
            files: files,
            name: name,
            inputPaths: inputPaths,
            outputPaths: outputPaths,
            inputFileListPaths: inputFileListPaths,
            outputFileListPaths: outputFileListPaths,
            shellPath: shellPath,
            shellScript: shellScript,
            buildActionMask: buildActionMask,
            runOnlyForDeploymentPostprocessing: runOnlyForDeploymentPostprocessing,
            showEnvVarsInLog: showEnvVarsInLog,
            alwaysOutOfDate: alwaysOutOfDate,
            dependencyFile: dependencyFile
        )
    }
}
