import Combine
import CombineExt
import Foundation
import TSCBasic
import TSCUtility
import TuistSupport
import TuistSupportTesting
@testable import TuistEnvKit

final class MockVersionProvider: VersionProviding {
    var invokedVersions = false
    var invokedVersionsCount = 0
    var stubbedVersionsResult: Result<[Version], Error>!

    func versions() -> AnyPublisher<[Version], Error> {
        invokedVersions = true
        invokedVersionsCount += 1
        return AnyPublisher(result: stubbedVersionsResult)
    }

    var invokedLatestVersion = false
    var invokedLatestVersionCount = 0
    var stubbedLatestVersionResult: Result<Version, Error>!

    func latestVersion() -> AnyPublisher<Version, Error> {
        invokedLatestVersion = true
        invokedLatestVersionCount += 1
        return AnyPublisher(result: stubbedLatestVersionResult)
    }
}
