import Foundation
import RxSwift
import TSCBasic
@testable import TuistCore

final class MockOtoolController: OtoolControlling {
    func dlybDependenciesPath(forBinaryAt _: AbsolutePath) throws -> Single<[AbsolutePath]> {
        .just([])
    }

    var dlybDependenciesPathStub: ((AbsolutePath) -> [String])?

    func dlybDependenciesPath(forBinaryAt path: AbsolutePath) throws -> [String] {
        dlybDependenciesPathStub?(path) ?? []
    }
}
