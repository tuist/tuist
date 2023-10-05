#if canImport(TuistCloud)
import Foundation
import TuistCloud
import TuistCore
import TuistLoader
import TuistSupport

protocol CloudAuthServicing: AnyObject {
    func authenticate(
        serverURL: String?
    ) throws
}

final class CloudAuthService: CloudAuthServicing {
    private let cloudSessionController: CloudSessionControlling
    private let cloudURLService: CloudURLServicing

    init(
        cloudSessionController: CloudSessionControlling = CloudSessionController(),
        cloudURLService: CloudURLServicing = CloudURLService()
    ) {
        self.cloudSessionController = cloudSessionController
        self.cloudURLService = cloudURLService
    }

    // MARK: - CloudAuthServicing

    func authenticate(
        serverURL: String?
    ) throws {
        let cloudURL = try cloudURLService.url(serverURL: serverURL)
        try cloudSessionController.authenticate(serverURL: cloudURL)
    }
}
#endif
