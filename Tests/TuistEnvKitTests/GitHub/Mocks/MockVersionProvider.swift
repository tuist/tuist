import Combine
import Foundation
import TSCBasic
import TSCUtility
import TuistSupport
import TuistSupportTesting
@testable import TuistEnvKit

final class MockVersionProvider: VersionProviding {
    var invokedVersions = false
    var invokedVersionsCount = 0
    var stubbedVersionsResult: [Version]!

    func versions() -> [Version] {
        invokedVersions = true
        invokedVersionsCount += 1
        return stubbedVersionsResult
    }

    var invokedLatestVersion = false
    var invokedLatestVersionCount = 0
    var stubbedLatestVersionResult: Version?

    func latestVersion() -> Version? {
        invokedLatestVersion = true
        invokedLatestVersionCount += 1
        return stubbedLatestVersionResult
    }
}
