import Foundation
import TSCBasic
import TuistCore
import TuistDependencies
import TuistLoader
import TuistSupport

// MARK: - DependenciesUpdateServiceError

enum DependenciesUpdateServiceError: FatalError {
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
            return "Updating dependencies is not yet supported. It's being worked on and it'll be available soon."
        }
    }
}

// MARK: - DependenciesUpdateService

final class DependenciesUpdateService {
    private let dependenciesController: DependenciesControlling
    private let dependenciesModelLoader: DependenciesModelLoading

    init(dependenciesController: DependenciesControlling = DependenciesController(),
         dependenciesModelLoader: DependenciesModelLoading = DependenciesModelLoader()) {
        self.dependenciesController = dependenciesController
        self.dependenciesModelLoader = dependenciesModelLoader
    }

    func run(path _: String?) throws {
        throw DependenciesUpdateServiceError.unimplemented
    }
}
