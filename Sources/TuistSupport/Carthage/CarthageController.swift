import Foundation
import TSCBasic
import TSCUtility

// MARK: - Carthage Controller Error

enum CarthageControllerError: FatalError, Equatable {
    /// Thrown when Carthage cannot be found in the environment.
    case carthageNotFound
    /// Thrown when version of Carthage cannot be determined.
    case unrecognizedCarthageVersion
    
    /// Error type.
    var type: ErrorType {
        switch self {
        case .carthageNotFound,
             .unrecognizedCarthageVersion:
            return .abort
        }
    }
    
    /// Error description.
    var description: String {
        switch self {
        case .carthageNotFound:
            return "Carthage was not found in the environment. It's possible that the tool is not installed or hasn't been exposed to your environment."
        case .unrecognizedCarthageVersion:
            return "Version of Carthage cannot be determined. It's possible that the tool is not installed or hasn't been exposed to your environment."
        }
    }
}

// MARK: - Carthage Controlling

/// Controls `Carthage` that can be found in the environment.
public protocol CarthageControlling {
    /// Returns true if Carthage is available in the environment.
    func canUseSystemCarthage() -> Bool
    
    /// Return version of Carthage that is available in the environment.
    func carthageVersion() throws -> Version
    
    /// Returns true if version of Carthage available in the environment supports producing XCFrameworks.
    func isXCFrameworksProductionSupported() throws -> Bool
}

// MARK: - Carthage Controller

public final class CarthageController: CarthageControlling {
    public init() { }
    
    public func canUseSystemCarthage() -> Bool {
        do {
            _ = try System.shared.which("carthage")
            return true
        } catch {
            return false
        }
    }
    
    public func carthageVersion() throws -> Version {
        guard let output = try? System.shared.capture("/usr/bin/env", "carthage", "version").spm_chomp() else {
            throw CarthageControllerError.carthageNotFound
        }
        
        guard let version = Version(string: output) else {
            throw CarthageControllerError.unrecognizedCarthageVersion
        }
        
        return version
    }
    
    public func isXCFrameworksProductionSupported() throws -> Bool {
        // Carthage has supported XCFrameworks production since 0.37.0
        // More info here: https://github.com/Carthage/Carthage/releases/tag/0.37.0
        try carthageVersion() >= Version(0, 37, 0)
    }
}
