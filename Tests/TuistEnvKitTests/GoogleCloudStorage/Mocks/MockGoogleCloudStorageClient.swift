import Foundation
import RxSwift
import SPMUtility
@testable import TuistEnvKit
@testable import TuistSupportTesting

final class MockGoogleCloudStorageClient: GoogleCloudStorageClienting {
    var latestVersionStub: Version?

    func latestVersion() -> Single<Version> {
        if let latestVersionStub = latestVersionStub {
            return Single.just(latestVersionStub)
        } else {
            return Single.error(TestError("Call to latestVersion not stubbed"))
        }
    }

    var latestTuistEnvURLStub: Foundation.URL?
    func latestTuistEnvURL() -> Foundation.URL {
        var components = URLComponents(url: URL.test(), resolvingAgainstBaseURL: true)!
        components.path = "tuistenv.zip"
        return latestTuistEnvURLStub ?? components.url!
    }

    var latestTuistURLStub: Foundation.URL?
    func latestTuistURL() -> Foundation.URL {
        var components = URLComponents(url: URL.test(), resolvingAgainstBaseURL: true)!
        components.path = "tuist.zip"
        return latestTuistURLStub ?? components.url!
    }
}
