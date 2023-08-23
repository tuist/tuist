import Foundation
import TuistCloud
import TuistCore
import TuistLoader
import TuistSupport

protocol CloudSessionServicing: AnyObject {
    /// It prints any existing session in the keychain to authenticate
    /// on a server identified by that URL.
    func printSession(
        serverURL: String?
    ) throws
}

final class CloudSessionService: CloudSessionServicing {
    private let cloudSessionController: CloudSessionControlling
    private let cloudURLService: CloudURLServicing

    // MARK: - Init

    init(
        cloudSessionController: CloudSessionControlling = CloudSessionController(),
        cloudURLService: CloudURLServicing = CloudURLService()
    ) {
        self.cloudSessionController = cloudSessionController
        self.cloudURLService = cloudURLService
    }

    // MARK: - CloudAuthServicing

    func printSession(
        serverURL: String?
    ) throws {
        let cloudURL = try cloudURLService.url(serverURL: serverURL)
        try cloudSessionController.printSession(serverURL: cloudURL)
    }
}
