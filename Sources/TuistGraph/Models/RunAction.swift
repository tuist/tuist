import Foundation
import TSCBasic

public struct RunAction: Equatable, Codable {
    // MARK: - Attributes

    public let configurationName: String
    public let executable: TargetReference?
    public let filePath: AbsolutePath?
    public let arguments: Arguments?
    public let options: RunActionOptions
    public let language: String?
    public let diagnosticsOptions: Set<SchemeDiagnosticsOption>

    // MARK: - Init

    public init(configurationName: String,
                executable: TargetReference?,
                filePath: AbsolutePath?,
                arguments: Arguments?,
                options: RunActionOptions = .init(),
                language: String? = nil,
                diagnosticsOptions: Set<SchemeDiagnosticsOption>)
    {
        self.configurationName = configurationName
        self.executable = executable
        self.filePath = filePath
        self.arguments = arguments
        self.options = options
        self.language = language
        self.diagnosticsOptions = diagnosticsOptions
    }
}
