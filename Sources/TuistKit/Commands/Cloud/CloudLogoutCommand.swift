import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistSigning
import TuistSupport

class CloudLogoutCommand: NSObject, Command {
    // MARK: - Attributes

    static let command = "logout"
    static let overview = "Removes any existing session to authenticate on the server with he URL defined in the Config.swift file."
    private let service = CloudLogoutService()

    // MARK: - Init

    public required init(parser: ArgumentParser) {
        _ = parser.add(subparser: CloudLogoutCommand.command, overview: CloudLogoutCommand.overview)
    }

    func run(with _: ArgumentParser.Result) throws {
        try service.logout()
    }
}
