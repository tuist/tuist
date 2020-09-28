import Foundation
import TSCBasic
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport

enum DependenciesUpdateServiceError: FatalError {
    case unimplemented
    
    var type: ErrorType {
        switch self {
        case .unimplemented:
            return .abort
        }
    }
    
    var description: String {
        switch self {
        case .unimplemented:
            return "Pssst! You have found secret and hidden part of project where we are trying to create something new and unexpected. We call it The Chimera Project. Stay alert!"
        }
    }
}

final class DependenciesUpdateService {
    init() { }
    
    func run(path: String?) throws {
        // TODO: implement me!
        throw DependenciesUpdateServiceError.unimplemented
    }
}
