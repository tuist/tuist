import Foundation

/// Target validation errors.
///
/// - missingSourceFiles: thrown when a target misses source files.
enum TargetValidatorError: FatalError, Equatable {
    case missingSourceFiles(target: String)

    var type: ErrorType {
        switch self {
        case .missingSourceFiles: return .abort
        }
    }

    var description: String {
        switch self {
        case let .missingSourceFiles(target):
            return "The target \(target) doesn't contain source files."
        }
    }

    /// Compares two instances of TargetValidatorError returning two if both instances are equal.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if both instances are equal.
    static func == (lhs: TargetValidatorError, rhs: TargetValidatorError) -> Bool {
        switch (lhs, rhs) {
        case let (.missingSourceFiles(lhsTarget), .missingSourceFiles(rhsTarget)):
            return lhsTarget == rhsTarget
        default:
            return false
        }
    }
}

class TargetValidator {
    /// It validates the given target.
    ///
    /// - Parameter target: target to be valdiated.
    /// - Throws: an error if the validation fails.
    func validate(target: Target) throws {
        try validateHasSourceFiles(target: target)
    }

    /// Validates that the target contains source files.
    ///
    /// - Parameter target: target to be validated.
    /// - Throws: an error if the target doesn't contain any sources.
    fileprivate func validateHasSourceFiles(target: Target) throws {
        let files = target.buildPhases.compactMap({ $0 as? SourcesBuildPhase })
            .flatMap({ $0.buildFiles })
            .flatMap({ $0.paths })
        if files.count == 0 {
        }
    }
}
