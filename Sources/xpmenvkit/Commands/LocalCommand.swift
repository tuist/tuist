import Basic
import Foundation
import Utility
import xpmcore

class LocalCommand: Command {
    static var command: String = "local"

    static var overview: String = "Creates a .xpm-version file that pins the version in the directory where the command is executed from."

    required init(parser _: ArgumentParser) {
    }

    func run(with _: ArgumentParser.Result) throws {
    }
}
