import Foundation
import Path

public struct ProfileAction: Equatable, Codable, Sendable {
    // MARK: - Attributes

    public let configurationName: String
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]
    public let executable: TargetReference?
    public let askForAppToLaunch: Bool
    public let arguments: Arguments?

    // MARK: - Init

    public init(
        configurationName: String,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        executable: TargetReference? = nil,
        askForAppToLaunch: Bool = false,
        arguments: Arguments? = nil
    ) {
        self.configurationName = configurationName
        self.preActions = preActions
        self.postActions = postActions
        self.executable = executable
        self.askForAppToLaunch = askForAppToLaunch
        self.arguments = arguments
    }
}

#if DEBUG
    extension ProfileAction {
        public static func test(
            configurationName: String = "Beta Release",
            preActions: [ExecutionAction] = [],
            postActions: [ExecutionAction] = [],
            // swiftlint:disable:next force_try
            executable: TargetReference? = TargetReference(projectPath: try! AbsolutePath(validating: "/Project"), name: "App"),
            askForAppToLaunch: Bool = false,
            arguments: Arguments? = Arguments.test()
        ) -> ProfileAction {
            ProfileAction(
                configurationName: configurationName,
                preActions: preActions,
                postActions: postActions,
                executable: executable,
                askForAppToLaunch: askForAppToLaunch,
                arguments: arguments
            )
        }
    }
#endif
