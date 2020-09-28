import Foundation
import RxBlocking
import TSCBasic
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport

enum DependenciesFetchServiceError: FatalError {
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

final class DependenciesFetchService {
    init() { }
    
    func run(path: String?) throws {
        // TODO: implement me!
        throw DependenciesFetchServiceError.unimplemented
    }
}
