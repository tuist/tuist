import Foundation

public enum SchemeDiagnosticsOption: String, Equatable, Codable {
    case enableAddressSanitizer
    case enableASanStackUseAfterReturn
    case enableThreadSanitizer
    case mainThreadChecker
    case performanceAntipatternChecker
}
