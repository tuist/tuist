import Foundation
import RxSwift
import struct TSCUtility.Version
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

    var latestTuistEnvBundleURLStub: Foundation.URL?
    func latestTuistEnvBundleURL() -> Foundation.URL {
        var components = URLComponents(url: URL.test(), resolvingAgainstBaseURL: true)!
        components.path = "tuistenv.zip"
        return latestTuistEnvBundleURLStub ?? components.url!
    }

    var latestTuistURLStub: Foundation.URL?
    func latestTuistURL() -> Foundation.URL {
        var components = URLComponents(url: URL.test(), resolvingAgainstBaseURL: true)!
        components.path = "tuist.zip"
        return latestTuistURLStub ?? components.url!
    }

    var tuistBundleURLStub: ((String) -> Foundation.URL?)?
    func tuistBundleURL(version: String) -> Observable<Foundation.URL?> {
        Observable.just(tuistBundleURLStub?(version) ?? nil)
    }
}
