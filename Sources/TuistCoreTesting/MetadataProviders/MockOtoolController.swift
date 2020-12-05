import Foundation
import RxSwift
import TSCBasic
@testable import TuistCore

final class MockOtoolController: OtoolControlling {

    var stubbedDlybDependenciesPathResult: Single<[AbsolutePath]>! = Single.just([])

    func dylibDependenciesBinaryPath(forBinaryAt path: AbsolutePath) throws -> Single<[AbsolutePath]> {
        return stubbedDlybDependenciesPathResult
    }
}
