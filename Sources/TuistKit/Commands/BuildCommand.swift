import Basic
import Foundation
import TuistCore
import Utility

enum BuildCommandError: FatalError {
    // Error description
    var description: String {
        return ""
    }

    // Error type
    var type: ErrorType { return .abort }
}

/// Command that builds a target from the project in the current directory.
class BuildCommand: NSObject, RawCommand {
    /// Command name.
    static var command: String = "build"

    /// Command description.
    static var overview: String = "Builds a project target."

    /// Printer instance to output the information to the user.
    let printer: Printing

    init(printer: Printing) {
        self.printer = printer
    }

    /// Main constructor.
    required convenience override init() {
        self.init(printer: Printer())
    }

    func run(arguments: [String]) throws {
        print(arguments)
    }
}
