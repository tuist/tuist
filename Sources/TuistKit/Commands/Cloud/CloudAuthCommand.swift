import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistSigning
import TuistSupport

class CloudAuthCommand: NSObject, Command {
    // MARK: - Attributes

    static let command = "auth"
    static let overview = "Authenticates the user on the server with the URL defined in the Config.swift file."
    private let cloudAuthService = CloudAuthService()

    // MARK: - Init

    public required init(parser: ArgumentParser) {
        _ = parser.add(subparser: CloudAuthCommand.command, overview: CloudAuthCommand.overview)
    }

    func run(with _: ArgumentParser.Result) throws {
        try cloudAuthService.authenticate()
    }
}
