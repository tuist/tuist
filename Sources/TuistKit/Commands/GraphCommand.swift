import Basic
import Foundation
import SPMUtility
import TuistCore

/// Command that generates and exports a dot graph from the workspace or project in the current directory.
class GraphCommand: NSObject, Command {
    /// Command name.
    static var command: String = "graph"

    /// Command description.
    static var overview: String = "Generates a dot graph from the workspace or project in the current directory."

    required init(parser: ArgumentParser) {
        let subParser = parser.add(subparser: GraphCommand.command, overview: GraphCommand.overview)
    }

    func run(with _: ArgumentParser.Result) throws {}
}
