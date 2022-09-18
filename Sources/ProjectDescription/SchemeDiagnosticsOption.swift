import Foundation

// TODO: refactor this to a struct in the next breaking release

/// Options to configure scheme diagnostics for run and test actions.
public enum SchemeDiagnosticsOption: String, Equatable, Codable {
    /// Enable the main thread cheker
    case mainThreadChecker

    /// Enable thread performance checker
    case performanceAntipatternChecker
}
