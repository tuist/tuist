import Foundation

/// Diagnostics options represent the configurable diagnostics-related settings in the schemes' run and test actions.
public enum SchemeDiagnosticsOption: String, Equatable, Codable {
    /// Enable the main thread cheker
    case mainThreadChecker
}
