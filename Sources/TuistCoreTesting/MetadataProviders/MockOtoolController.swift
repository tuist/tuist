import Foundation
import TSCBasic
import RxSwift
@testable import TuistCore

final class MockOtoolController: OtoolControlling {
    func dlybDependenciesPath(forBinaryAt path: AbsolutePath) throws -> Single<[AbsolutePath]> {
        .just([])
    }


    var dlybDependenciesPathStub: ((AbsolutePath) -> [String])?

    func dlybDependenciesPath(forBinaryAt path: AbsolutePath) throws -> [String] {
        return dlybDependenciesPathStub?(path) ?? []
    }

}
