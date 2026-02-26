import Foundation
import Path

public struct RunAction: Equatable, Codable, Sendable {
    // MARK: - Attributes

    public let configurationName: String
    public let attachDebugger: Bool
    public let customLLDBInitFile: AbsolutePath?
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]
    public let executable: TargetReference?
    public let filePath: AbsolutePath?
    public let arguments: Arguments?
    public let options: RunActionOptions
    public let diagnosticsOptions: SchemeDiagnosticsOptions
    public let metalOptions: MetalOptions?
    public let expandVariableFromTarget: TargetReference?
    public let askForAppToLaunch: Bool
    public let launchStyle: LaunchStyle
    public let appClipInvocationURL: URL?
    public var customWorkingDirectory: AbsolutePath?
    public var useCustomWorkingDirectory: Bool

    // MARK: - Init

    public init(
        configurationName: String,
        attachDebugger: Bool,
        customLLDBInitFile: AbsolutePath?,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        executable: TargetReference?,
        filePath: AbsolutePath?,
        arguments: Arguments?,
        options: RunActionOptions = .init(),
        diagnosticsOptions: SchemeDiagnosticsOptions,
        metalOptions: MetalOptions? = nil,
        expandVariableFromTarget: TargetReference? = nil,
        askForAppToLaunch: Bool = false,
        launchStyle: LaunchStyle = .automatically,
        appClipInvocationURL: URL? = nil,
        customWorkingDirectory: AbsolutePath? = nil,
        useCustomWorkingDirectory: Bool = false
    ) {
        self.configurationName = configurationName
        self.attachDebugger = attachDebugger
        self.customLLDBInitFile = customLLDBInitFile
        self.preActions = preActions
        self.postActions = postActions
        self.executable = executable
        self.filePath = filePath
        self.arguments = arguments
        self.options = options
        self.diagnosticsOptions = diagnosticsOptions
        self.metalOptions = metalOptions
        self.expandVariableFromTarget = expandVariableFromTarget
        self.askForAppToLaunch = askForAppToLaunch
        self.launchStyle = launchStyle
        self.appClipInvocationURL = appClipInvocationURL
        self.customWorkingDirectory = customWorkingDirectory
        self.useCustomWorkingDirectory = useCustomWorkingDirectory
    }
}

#if DEBUG
    extension RunAction {
        public static func test(
            configurationName: String = BuildConfiguration.debug.name,
            attachDebugger: Bool = true,
            customLLDBInitFile: AbsolutePath? = nil,
            preActions: [ExecutionAction] = [],
            postActions: [ExecutionAction] = [],
            // swiftlint:disable:next force_try
            executable: TargetReference? = TargetReference(projectPath: try! AbsolutePath(validating: "/Project"), name: "App"),
            filePath: AbsolutePath? = nil,
            arguments: Arguments? = Arguments.test(),
            options: RunActionOptions = .init(),
            diagnosticsOptions: SchemeDiagnosticsOptions = XcodeGraph.SchemeDiagnosticsOptions(
                mainThreadCheckerEnabled: true,
                performanceAntipatternCheckerEnabled: true
            ),
            metalOptions: MetalOptions? = XcodeGraph.MetalOptions(
                apiValidation: true
            ),
            expandVariableFromTarget: TargetReference? = nil,
            askForAppToLaunch: Bool = false,
            launchStyle: LaunchStyle = .automatically,
            appClipInvocationURL: URL? = nil,
            customWorkingDirectory: AbsolutePath? = nil,
            useCustomWorkingDirectory: Bool = false
        ) -> RunAction {
            RunAction(
                configurationName: configurationName,
                attachDebugger: attachDebugger,
                customLLDBInitFile: customLLDBInitFile,
                preActions: preActions,
                postActions: postActions,
                executable: executable,
                filePath: filePath,
                arguments: arguments,
                options: options,
                diagnosticsOptions: diagnosticsOptions,
                metalOptions: metalOptions,
                expandVariableFromTarget: expandVariableFromTarget,
                askForAppToLaunch: askForAppToLaunch,
                launchStyle: launchStyle,
                appClipInvocationURL: appClipInvocationURL,
                customWorkingDirectory: customWorkingDirectory,
                useCustomWorkingDirectory: useCustomWorkingDirectory
            )
        }
    }
#endif
