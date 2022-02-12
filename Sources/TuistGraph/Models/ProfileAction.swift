import Foundation

public struct ProfileAction: Equatable, Codable {
    // MARK: - Attributes

    public let configurationName: String
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]
    public let executable: TargetReference?
    public let arguments: Arguments?

    // MARK: - Init

    public init(
        configurationName: String,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        executable: TargetReference? = nil,
        arguments: Arguments? = nil
    ) {
        self.configurationName = configurationName
        self.preActions = preActions
        self.postActions = postActions
        self.executable = executable
        self.arguments = arguments
    }
}
