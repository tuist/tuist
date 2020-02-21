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
}
