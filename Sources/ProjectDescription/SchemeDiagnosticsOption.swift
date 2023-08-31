import Foundation

// TODO: refactor this to a struct in the next breaking release

/// Options to configure scheme diagnostics for run and test actions.
public enum SchemeDiagnosticsOption: String, Equatable, Codable {
    /// Enable the address sanitizer
    case enableAddressSanitizer

    /// Enable the detect use of stack after return of address sanitizer
    case enableDetectStackUseAfterReturn

    /// Enable the thread sanitizer
    case enableThreadSanitizer

    /// Enable the main thread cheker
    case mainThreadChecker

    /// Enable thread performance checker
    case performanceAntipatternChecker
}
