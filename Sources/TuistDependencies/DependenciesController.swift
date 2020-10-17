import TSCBasic
import TuistSupport

// MARK: - Dependencies Controller Errors

public enum DependenciesControllerError: FatalError {
    case unimplemented
    
    /// Error type.
    public var type: ErrorType {
        switch self {
        case .unimplemented:
            return .abort
        }
    }
    
    /// Description.
    public var description: String {
        switch self {
        case .unimplemented:
            return "Pssst! You have found secret and hidden part of project where we are trying to create something new and unexpected. We call it The Chimera Project. Stay alert!"
        }
    }
}

// MARK: - Dependencies Controlling

/// `DependenciesControlling` controls:
///     1. Fetching/updating dependencies defined in `./Tuist/Dependencies.swift` by running appropriate dependencies managers (`Cocoapods`, `Carthage`, `SPM`).
///     2. Compiling fetched/updated depedencies into `.framework.`/`.xcframework.`.
///     3. Saving complited frameworks uder `./Tuist/Dependencies/*`.
public protocol DependenciesControlling {
    /// Fetches dependencies.
    /// - Parameter path: Directory whose project's dependencies will be fetched.
    func fetch(at path: AbsolutePath) throws
    /// Updates dependencies.
    /// - Parameter path: Directory whose project's dependencies will be updated.
    func update(at path: AbsolutePath) throws
}

// MARK: - Dependencies Controller

public final class DependenciesController: DependenciesControlling {
    public init() { }
    
    public func fetch(at path: AbsolutePath) throws {
        logger.notice("Start fetching depednencies.")
        
        // TODO: implement me!
        throw DependenciesControllerError.unimplemented
    }
    
    public func update(at path: AbsolutePath) throws {
        logger.notice("Start updating depednencies.")
        
        // TODO: implement me!
        throw DependenciesControllerError.unimplemented
    }
}
