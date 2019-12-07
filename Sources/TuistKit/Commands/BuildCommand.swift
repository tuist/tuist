import Basic
import Foundation
import SPMUtility
import TuistSupport

enum BuildCommandError: FatalError {
    // Error description
    var description: String {
        ""
    }

    // Error type
    var type: ErrorType { .abort }
}

/// Command that builds a target from the project in the current directory.
class BuildCommand: NSObject, RawCommand {
    /// Command name.
    static var command: String = "build"

    /// Command description.
    static var overview: String = "Builds a project target."

    /// Default constructor.
    required override init() {
        super.init()
    }

    func run(arguments _: [String]) throws {
        Printer.shared.print("Command not available yet")
    }
}
