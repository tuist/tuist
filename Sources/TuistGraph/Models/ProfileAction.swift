import Foundation

public struct ProfileAction: Equatable {
    // MARK: - Attributes

    public let configurationName: String
    public let executable: TargetReference?
    public let arguments: Arguments?

    // MARK: - Init

    public init(configurationName: String,
                executable: TargetReference? = nil,
                arguments: Arguments? = nil)
    {
        self.configurationName = configurationName
        self.executable = executable
        self.arguments = arguments
    }
}
