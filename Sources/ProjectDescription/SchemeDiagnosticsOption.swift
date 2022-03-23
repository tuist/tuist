import Foundation

/// Options to configure scheme diagnostics for run and test actions.
public enum SchemeDiagnosticsOption: String, Equatable, Codable {
    /// Enable the main thread cheker
    case mainThreadChecker
}
