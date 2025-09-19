import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

/// Represents specific errors that can occur during the mapping of App Clip data.
enum AppClipMappingError: LocalizedError {
    /// Thrown when the provided App Clip invocation URL string is not a valid URL.
    ///
    /// - Parameter urlString: The original invalid URL string.
    case invalidInvocationURL(String)

    /// A human-readable description of the error, useful for debugging or displaying in UI.
    var errorDescription: String? {
        switch self {
        case let .invalidInvocationURL(urlString):
            return "The provided App Clip invocation URL string is invalid: '\(urlString)'. Make sure it is a properly formatted URL."
        }
    }
}

extension XcodeGraph.RunAction {
    /// Maps a ProjectDescription.RunAction instance into a XcodeGraph.RunAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the settings.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.RunAction,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.RunAction {
        let configurationName = manifest.configuration.rawValue

        let customLLDBInitFile = try manifest.customLLDBInitFile.map {
            try generatorPaths.resolve(path: $0)
        }

        let preActions = try manifest.preActions.map {
            try XcodeGraph.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let postActions = try manifest.postActions.map {
            try XcodeGraph.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let arguments = manifest.arguments.map { XcodeGraph.Arguments.from(manifest: $0) }

        var executableResolved: XcodeGraph.TargetReference?
        if let executable = manifest.executable {
            executableResolved = TargetReference(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath(executable.projectPath),
                name: executable.targetName
            )
        }

        var filePathResolved: AbsolutePath?
        if let filePath = manifest.filePath {
            filePathResolved = try generatorPaths.resolve(path: filePath)
        }

        var useCustomWorkingDirectory = false
        var customWorkingDirectoryResolved: AbsolutePath?
        if let customWorkingDirectory = manifest.customWorkingDirectory {
            customWorkingDirectoryResolved = try generatorPaths.resolve(path: customWorkingDirectory)
            useCustomWorkingDirectory = true
        }

        let options = try XcodeGraph.RunActionOptions.from(manifest: manifest.options, generatorPaths: generatorPaths)

        let diagnosticsOptions = XcodeGraph.SchemeDiagnosticsOptions.from(manifest: manifest.diagnosticsOptions)

        let metalOptions = XcodeGraph.MetalOptions.from(manifest: manifest.metalOptions)

        let expandVariablesFromTarget: XcodeGraph.TargetReference?
        expandVariablesFromTarget = try manifest.expandVariableFromTarget.map {
            XcodeGraph.TargetReference(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                name: $0.targetName
            )
        }

        let launchStyle = XcodeGraph.LaunchStyle.from(manifest: manifest.launchStyle)

        var appClipInvocationURL: URL?
        if let appClipInvocationURLString = manifest.appClipInvocationURLString {
            if let url = URL(string: appClipInvocationURLString) {
                appClipInvocationURL = url
            } else {
                throw AppClipMappingError.invalidInvocationURL(appClipInvocationURLString)
            }
        }

        return XcodeGraph.RunAction(
            configurationName: configurationName,
            attachDebugger: manifest.attachDebugger,
            customLLDBInitFile: customLLDBInitFile,
            preActions: preActions,
            postActions: postActions,
            executable: executableResolved,
            filePath: filePathResolved,
            arguments: arguments,
            options: options,
            diagnosticsOptions: diagnosticsOptions,
            metalOptions: metalOptions,
            expandVariableFromTarget: expandVariablesFromTarget,
            launchStyle: launchStyle,
            appClipInvocationURL: appClipInvocationURL,
            customWorkingDirectory: customWorkingDirectoryResolved,
            useCustomWorkingDirectory: useCustomWorkingDirectory
        )
    }
}
