import Foundation
import TSCBasic

public struct RunAction: Equatable {
    // MARK: - Attributes

    public let configurationName: String
    public let executable: TargetReference?
    public let filePath: AbsolutePath?
    public let arguments: Arguments?

    // MARK: - Init

    public init(configurationName: String,
                executable: TargetReference? = nil,
                filePath: AbsolutePath? = nil,
                arguments: Arguments? = nil) {
        self.configurationName = configurationName
        self.executable = executable
        self.filePath = filePath
        self.arguments = arguments
    }
}
