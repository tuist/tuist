import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistSigning
import TuistSupport

class CloudSessionCommand: NSObject, Command {
    // MARK: - Attributes

    static let command = "session"
    static let overview = "Prints any existing session to authenticate on the server with the URL defined in the Config.swift file."
    private let service = CloudSessionService()

    // MARK: - Init

    public required init(parser: ArgumentParser) {
        _ = parser.add(subparser: CloudSessionCommand.command, overview: CloudSessionCommand.overview)
    }

    func run(with _: ArgumentParser.Result) throws {
        try service.printSession()
    }
}
