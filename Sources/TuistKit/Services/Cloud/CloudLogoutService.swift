import Foundation
import TuistCloud
import TuistCore
import TuistLoader
import TuistSupport

protocol CloudLogoutServicing: AnyObject {
    /// It removes any session associated to that domain from
    /// the keychain
    func logout(
        serverURL: String?
    ) throws
}

final class CloudLogoutService: CloudLogoutServicing {
    private let cloudSessionController: CloudSessionControlling
    private let cloudURLService: CloudURLServicing

    init(
        cloudSessionController: CloudSessionControlling = CloudSessionController(),
        cloudURLService: CloudURLServicing = CloudURLService()
    ) {
        self.cloudSessionController = cloudSessionController
        self.cloudURLService = cloudURLService
    }

    func logout(
        serverURL: String?
    ) throws {
        let cloudURL = try cloudURLService.url(serverURL: serverURL)
        try cloudSessionController.logout(serverURL: cloudURL)
    }
}
