import Foundation
import RxSwift
import TSCBasic
@testable import TuistCore

final class MockOtoolController: OtoolControlling {
    var dlybDependenciesPathStub: ((AbsolutePath) -> Single<[AbsolutePath]>)?

    func dlybDependenciesPath(forBinaryAt path: AbsolutePath) throws -> Single<[AbsolutePath]> {
        if let dlybDependenciesPathStub = dlybDependenciesPathStub {
            return dlybDependenciesPathStub(path)
        }
        return .just([])
    }
}
