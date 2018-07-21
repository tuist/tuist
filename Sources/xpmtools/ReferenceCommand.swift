import Basic
import Foundation
import Utility
import xpmcore

class ReferenceCommand: NSObject, Command {
    
    // MARK: - Command
    
    static let command = "reference"
    static let overview = "Generates the reference for xpm."
    
    // MARK: - Attributes
    
    private let shell: Shelling
    
    // MARK: - Init
    
    required convenience init(parser: ArgumentParser) {
        self.init(parser: parser, shell: Shell())
    }
    
    init(parser: ArgumentParser, shell: Shelling) {
        _ = parser.add(subparser: ReferenceCommand.command, overview: ReferenceCommand.overview)
        self.shell = shell
    }

    public func run(with _: ArgumentParser.Result) throws {
        shell.
        // Check if jazzy exists
        // Generate the project
        
//        try Process.checkNonZeroExit(args: "swift", "build", "--configuration", "release")
    }
}
