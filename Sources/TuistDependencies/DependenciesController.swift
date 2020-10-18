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
            return "A standard approach for managing third-party dependencies is being worked on and it'll be available soon."
        }
    }
}

// MARK: - Dependencies Controlling

/// `DependenciesControlling` controls:
///     1. Fetching/updating dependencies defined in `./Tuist/Dependencies.swift` by running appropriate dependencies managers (`Cocoapods`, `Carthage`, `SPM`).
///     2. Compiling fetched/updated depedencies into `.framework.`/`.xcframework.`.
///     3. Saving compiled frameworks uder `./Tuist/Dependencies/*`.
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
    private let carthageManager: CarthageManaging
    
    public init(carthageManager: CarthageManaging = CarthageManager()) {
        self.carthageManager = carthageManager
    }

    public func fetch(at _: AbsolutePath) throws {
        logger.notice("Start fetching depednencies.")

        // TODO: implement me!
        throw DependenciesControllerError.unimplemented
    }

    public func update(at _: AbsolutePath) throws {
        logger.notice("Start updating depednencies.")

        // TODO: implement me!
        throw DependenciesControllerError.unimplemented
    }
}
