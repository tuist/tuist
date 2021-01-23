import Foundation
import TSCBasic

public struct RunAction: Equatable {
    // MARK: - Attributes

    public let configurationName: String
    public let executable: TargetReference?
    public let filePath: AbsolutePath?
    public let arguments: Arguments?
    public let diagnosticsOptions: Set<SchemeDiagnosticsOption>

    // MARK: - Init

    public init(configurationName: String,
                executable: TargetReference?,
                filePath: AbsolutePath?,
                arguments: Arguments?,
                diagnosticsOptions: Set<SchemeDiagnosticsOption>)
    {
        self.configurationName = configurationName
        self.executable = executable
        self.filePath = filePath
        self.arguments = arguments
        self.diagnosticsOptions = diagnosticsOptions
    }
}
